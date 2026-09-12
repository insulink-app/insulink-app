import 'package:insulink/src/pump/protocol/pod_basal_elements.dart';

/// Groups a per-slot pulse list into the runs the interlock encodes.
///
/// A run is at most 16 slots. Beyond plain equal runs it recognises the pod's
/// alternating pattern — where an odd hourly pulse count makes consecutive
/// slots differ by one — so such a stretch encodes as a single run with the
/// alternate flag instead of many one-slot runs. Both the full-day schedule and
/// a temporary rate are grouped by this same code, because the pod checks the
/// two encodings of a program against each other.
class PodPulseRuns {
  PodPulseRuns(this.pulsesPerSlot);

  static const int _maxSlotsPerRun = 16;

  final List<int> pulsesPerSlot;

  List<PodBasalShortElement> get elements {
    final perSlot = pulsesPerSlot;
    final elements = <PodBasalShortElement>[];
    var alternates = false;
    var previous = 0;
    var slotsInElement = 0;
    var slot = 0;

    void flush() {
      elements.add(
        PodBasalShortElement(
          slotCount: slotsInElement,
          pulsesPerSlot: previous,
          extraAlternatePulse: alternates,
        ),
      );
    }

    while (slot < perSlot.length) {
      if (slot == 0) {
        previous = perSlot[0];
        slotsInElement = 1;
        slot++;
        continue;
      }
      if (perSlot[slot] == previous) {
        if (slotsInElement < _maxSlotsPerRun) {
          slotsInElement++;
        } else {
          flush();
          previous = perSlot[slot];
          slotsInElement = 1;
          alternates = false;
        }
        slot++;
        continue;
      }
      final startsAlternating =
          slotsInElement == 1 && !alternates && perSlot[slot] == previous + 1;
      if (startsAlternating) {
        slot++;
        slotsInElement++;
        alternates = true;
        var expectExtraNext = false;
        while (slot < perSlot.length) {
          final stillAlternating =
              perSlot[slot] == previous + (expectExtraNext ? 1 : 0);
          if (!stillAlternating || slotsInElement >= _maxSlotsPerRun) {
            flush();
            previous = perSlot[slot];
            slotsInElement = 1;
            alternates = false;
            slot++;
            break;
          }
          expectExtraNext = !expectExtraNext;
          slotsInElement++;
          slot++;
        }
        continue;
      }
      flush();
      previous = perSlot[slot];
      slotsInElement = 1;
      alternates = false;
      slot++;
    }
    flush();
    return elements;
  }
}
