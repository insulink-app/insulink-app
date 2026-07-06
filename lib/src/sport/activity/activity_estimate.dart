/// Walking estimates used wherever real Health data is absent — the Today tiles
/// and the detail page's today row must show the SAME number. Distance = steps ×
/// stride; calories ≈ distance × weight × 0.9 (a rough walking burn).
double estimatedDistanceKm(int steps, int strideCm) => steps * strideCm / 100000;

double estimatedCalories(double distanceKm, double weightKg) =>
    distanceKm * weightKg * 0.9;
