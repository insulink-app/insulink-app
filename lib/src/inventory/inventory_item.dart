/// How urgently an item needs restocking, derived (never stored).
enum StockStatus { ok, low, shortage }

/// What kind of supply an item is. A [sensor] carries a [SensorBrand] and a
/// [pump] a [PumpBrand]; both take part in the auto-decrement when a new one is
/// paired.
enum ItemType {
  sensor('sensor'),
  pump('pump'),
  other('other');

  const ItemType(this.wireKey);
  final String wireKey;

  static ItemType fromWireKey(String? key) => ItemType.values.firstWhere(
    (type) => type.wireKey == key,
    orElse: () => ItemType.other,
  );
}

/// Which CGM a sensor item restocks, so a newly paired Libre/Dexcom sensor
/// pulls one from the matching item.
enum SensorBrand {
  libre('libre'),
  dexcom('dexcom'),
  other('other');

  const SensorBrand(this.wireKey);
  final String wireKey;

  /// Typical days one unit lasts for the known brands (a G7 ~10, a Libre 3 ~14).
  /// Null for [other], where the user enters the duration themselves.
  double? get typicalDaysPerUnit => switch (this) {
    SensorBrand.libre => 14,
    SensorBrand.dexcom => 10,
    SensorBrand.other => null,
  };

  static SensorBrand? fromWireKey(String? key) {
    if (key == null) {
      return null;
    }
    return SensorBrand.values.firstWhere(
      (brand) => brand.wireKey == key,
      orElse: () => SensorBrand.other,
    );
  }
}

/// Which pump a pod item restocks, so a newly activated pod pulls one from the
/// matching item.
///
/// Shaped exactly like [SensorBrand], because it does the same job: it names the
/// hardware so the right item is decremented, and it carries the run time so the
/// user does not have to look it up.
enum PumpBrand {
  omnipodDash('omnipod_dash'),
  other('other');

  const PumpBrand(this.wireKey);
  final String wireKey;

  /// Days one unit lasts. A DASH pod is rated for 72 hours; the extra 8 hours of
  /// grace are deliberately NOT counted, because stock planning should assume the
  /// pod is replaced on schedule rather than run into its reserve.
  double? get typicalDaysPerUnit => switch (this) {
    PumpBrand.omnipodDash => 3,
    PumpBrand.other => null,
  };

  static PumpBrand? fromWireKey(String? key) {
    if (key == null) {
      return null;
    }
    return PumpBrand.values.firstWhere(
      (brand) => brand.wireKey == key,
      orElse: () => PumpBrand.other,
    );
  }
}

/// One scheduled delivery: when it arrives and how many units.
class Delivery {
  const Delivery({required this.atEpochMs, required this.quantity});

  final int atEpochMs;
  final int quantity;

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(atEpochMs);

  factory Delivery.fromJson(Map<String, dynamic> json) => Delivery(
    atEpochMs: json['at'] as int,
    quantity: json['quantity'] as int,
  );

  Map<String, dynamic> toJson() => {'at': atEpochMs, 'quantity': quantity};
}

/// A tracked supply (sensor, pod, cannula, …). Only the raw facts are stored —
/// stock, weekly consumption and the planned deliveries. Everything the UI
/// shows (run-out date, surplus, warning status) is DERIVED from those by the
/// methods below, so there is no forecast state that can drift.
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.stock,
    required this.baseStock,
    required this.daysPerUnit,
    required this.anchorMs,
    this.type = ItemType.other,
    this.sensorBrand,
    this.pumpBrand,
    this.deliveries = const [],
  });

  final String id;
  final String name;

  /// How many units are on hand right now.
  final int stock;

  /// The full/target amount ("Grundbestand") — the denominator of the stock
  /// bar. A restock brings [stock] back up towards this.
  final int baseStock;

  /// How many days a single unit lasts (a G7 sensor ~10, a pod ~3). Drives the
  /// consumption rate; 0 means "don't forecast" (never runs out).
  final double daysPerUnit;
  final ItemType type;

  /// The CGM this item restocks — set only when [type] is [ItemType.sensor].
  final SensorBrand? sensorBrand;

  /// The pump this item restocks — set only when [type] is [ItemType.pump].
  final PumpBrand? pumpBrand;
  final List<Delivery> deliveries;

  /// Epoch-ms the time-based consumption is measured from. Reset whenever the
  /// user declares the stock (editor save, +/- , direct input); advanced by
  /// [withTimeDecay] as whole units are consumed. Sensors ignore it (they are
  /// decremented on pairing, not by elapsed time).
  final int anchorMs;

  /// Vorwarnzeit für die Low-Warnung (Artikel ohne geplante Lieferung).
  // ponytail: fixe Vorwarnzeit, pro-Artikel-Feld erst wenn jemand es braucht.
  static const lowStockLeadDays = 7;

  double get perDay => daysPerUnit > 0 ? 1 / daysPerUnit : 0;

  static double _daysBetween(DateTime from, DateTime to) =>
      to.difference(from).inMilliseconds / Duration.millisecondsPerDay;

  /// When the current stock runs out at the current rate — null if nothing is
  /// consumed (no per-unit duration), because then it never runs out.
  DateTime? runOutDate(DateTime now) {
    if (perDay <= 0) {
      return null;
    }
    return now.add(
      Duration(milliseconds: (stock / perDay * Duration.millisecondsPerDay).round()),
    );
  }

  /// The next delivery still to come, or null if none is scheduled.
  Delivery? nextDelivery(DateTime now) {
    final upcoming =
        deliveries.where((delivery) => delivery.atEpochMs >= now.millisecondsSinceEpoch).toList()
          ..sort((left, right) => left.atEpochMs.compareTo(right.atEpochMs));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  /// Projected stock the instant BEFORE [target] — consumption subtracted and
  /// every delivery strictly before [target] added, but not one landing on it.
  double projectedStockBefore(DateTime now, DateTime target) {
    final consumed = perDay * _daysBetween(now, target);
    final incoming = deliveries
        .where((delivery) =>
            delivery.atEpochMs >= now.millisecondsSinceEpoch &&
            delivery.atEpochMs < target.millisecondsSinceEpoch)
        .fold(0, (sum, delivery) => sum + delivery.quantity);
    return stock - consumed + incoming;
  }

  /// Stock left the instant BEFORE the next delivery arrives, assuming
  /// everything goes to plan — the leftover that carries over ("Überschuss vor
  /// Lieferung"). Null if no delivery is scheduled.
  double? surplusBeforeNextDelivery(DateTime now) {
    final next = nextDelivery(now);
    if (next == null) {
      return null;
    }
    return projectedStockBefore(now, next.date);
  }

  /// Warning level: runs out before the next delivery → shortage; no delivery
  /// and running out within the lead time → low; otherwise ok.
  StockStatus status(DateTime now) {
    if (perDay <= 0) {
      return StockStatus.ok;
    }
    final next = nextDelivery(now);
    if (next != null) {
      return projectedStockBefore(now, next.date) < 0
          ? StockStatus.shortage
          : StockStatus.ok;
    }
    final cutoff = now.add(const Duration(days: lowStockLeadDays));
    return runOutDate(now)!.isBefore(cutoff) ? StockStatus.low : StockStatus.ok;
  }

  /// Whether a unit leaves this item when hardware is PAIRED rather than as time
  /// passes.
  ///
  /// True for anything the app actually pairs: a sensor, and a pod of a pump the
  /// driver supports. Counting those by elapsed time as well would take two units
  /// out of stock for one piece of hardware.
  ///
  /// A pump the app cannot pair ([PumpBrand.other]) is not in that group, so it
  /// falls back to the time-based estimate like any other supply.
  bool get isConsumedOnPairing =>
      type == ItemType.sensor ||
      (type == ItemType.pump && pumpBrand == PumpBrand.omnipodDash);

  /// Fraction of the base stock still on hand, clamped to 0..1 for the bar.
  double get stockFraction {
    if (baseStock <= 0) {
      return 0;
    }
    return (stock / baseStock).clamp(0.0, 1.0);
  }

  /// Apply elapsed-time consumption for items that have a per-unit
  /// duration: one unit is consumed per [daysPerUnit] elapsed since [anchorMs],
  /// with the anchor advanced by the consumed periods (the remainder is kept).
  /// Items decremented on pairing return unchanged; see [isConsumedOnPairing].
  /// Returns the same instance when nothing is due, so callers can skip a write.
  // ponytail: accrued lazily on load/refresh, no background timer — a unit
  // "ticks off" the next time the app reads the inventory, not on the second.
  InventoryItem withTimeDecay(DateTime now) {
    if (isConsumedOnPairing || daysPerUnit <= 0 || stock <= 0) {
      return this;
    }
    final elapsedDays =
        (now.millisecondsSinceEpoch - anchorMs) / Duration.millisecondsPerDay;
    final due = (elapsedDays / daysPerUnit).floor();
    if (due <= 0) {
      return this;
    }
    final consumed = due > stock ? stock : due;
    final advancedAnchor = anchorMs +
        (consumed * daysPerUnit * Duration.millisecondsPerDay).round();
    return copyWith(stock: stock - consumed, anchorMs: advancedAnchor);
  }

  InventoryItem copyWith({int? stock, int? anchorMs}) => InventoryItem(
    id: id,
    name: name,
    stock: stock ?? this.stock,
    baseStock: baseStock,
    daysPerUnit: daysPerUnit,
    anchorMs: anchorMs ?? this.anchorMs,
    type: type,
    sensorBrand: sensorBrand,
    pumpBrand: pumpBrand,
    deliveries: deliveries,
  );

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
    id: json['id'] as String,
    name: json['name'] as String,
    stock: json['stock'] as int,
    baseStock: json['base_stock'] as int? ?? json['stock'] as int,
    daysPerUnit: (json['days_per_unit'] as num?)?.toDouble() ?? 0,
    anchorMs: json['anchor_ms'] as int? ??
        DateTime.now().millisecondsSinceEpoch,
    type: ItemType.fromWireKey(json['type'] as String?),
    sensorBrand: SensorBrand.fromWireKey(json['sensor_brand'] as String?),
    pumpBrand: PumpBrand.fromWireKey(json['pump_brand'] as String?),
    deliveries: (json['deliveries'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(Delivery.fromJson)
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'stock': stock,
    'base_stock': baseStock,
    'days_per_unit': daysPerUnit,
    'anchor_ms': anchorMs,
    'type': type.wireKey,
    if (sensorBrand != null) 'sensor_brand': sensorBrand!.wireKey,
    if (pumpBrand != null) 'pump_brand': pumpBrand!.wireKey,
    'deliveries': deliveries.map((delivery) => delivery.toJson()).toList(),
  };
}
