# Forecast evaluation (Analysis → Forecast)

How the app scores the glucose forecast against what the sensor actually read.
Spans three repos; this file is the contract between them.

## Where the work happens

| Step | Where |
|---|---|
| Replay the user's model over its stored history | `insulink-predictor` `POST /backtest` (`serve/app.py`) |
| Forward it, scoped to the caller's `user_id` | `insulink-api` `POST /v1/glucose/predict/backtest/` |
| Match against local readings, score, draw | `lib/src/analysis/forecast/` |

The predictor returns **forecasts only, never outcomes**. The readings a forecast
is judged against are the ones on this device (`CgmController.statsArchive`), so
the comparison — and every number the user sees — happens on the phone.

## The wire shape

```
POST /v1/glucose/predict/backtest/   {"horizon": 30|60, "hours": 1..168}
-> {"horizon_min": 30, "grid_minutes": 5, "points": [
     {"ts": <epoch_ms>, "mgdl": 132.0, "anchor_mgdl": 128.0,
      "lo_mgdl": 118.0, "hi_mgdl": 151.0}, ...]}
```

One point per five-minute bucket. `ts` is when the forecast was made; it predicts
`ts + horizon_min`. `anchor_mgdl` is the reading the anchor sat on — the
persistence baseline `ŷ_{t+h} = g_t` — so the skill score needs nothing else from
the backend. `lo`/`hi` are the conformal q10/q90 band and are absent for a model
trained before the band existed.

## What the numbers mean

* **Skill score** `1 − RMSE_model / RMSE_persistence`. Zero means the model did
  exactly as well as assuming glucose stays put, which is a strong baseline on a
  flat stretch. The value lives in the excursions — see the predictor's ROADMAP.
* **Inside band** is scored on `lo`/`hi`, not on the point forecast: the point is
  a conditional mean and rarely reaches a low or a high on its own. A calibrated
  band sits near 80%.
* Anchors over a sensor gap are excluded by the predictor, and a target time with
  no reading within three minutes is dropped by the app. Neither side
  interpolates over a gap.

## The caveat that must stay on screen

The backtest is **in-sample**: each user's model is retrained daily on the very
history it is replayed over, so these residuals flatter it. It answers "how did
the forecast track my day", not "how will it generalise". The honest
out-of-sample number is the walk-forward evaluation in the predictor's
`evaluation/`, and `analysis.forecast.hint` says so in the UI.
