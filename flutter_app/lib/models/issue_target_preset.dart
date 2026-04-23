class IssueTargetPreset {
  final String issueTarget;
  final String? vehiclePlate;
  final int? driverId;
  final String? driverName;

  const IssueTargetPreset({
    required this.issueTarget,
    this.vehiclePlate,
    this.driverId,
    this.driverName,
  });

  bool get hasReusableTarget {
    if (issueTarget == 'vehicle') {
      return vehiclePlate != null && vehiclePlate!.trim().isNotEmpty;
    }
    if (issueTarget == 'driver') {
      return driverId != null && driverName != null && driverName!.trim().isNotEmpty;
    }
    return false;
  }

  static IssueTargetPreset? fromHistoryItem(Map<String, dynamic> item) {
    final issueTarget = (item['issue_target'] as String?)?.trim();
    if (issueTarget == null || issueTarget.isEmpty) {
      return null;
    }

    final vehiclePlate = (item['vehicle_plate'] as String?)?.trim();
    final driverName = (item['driver_name'] as String?)?.trim();
    final driverIdRaw = item['driver_id'];
    final driverId = switch (driverIdRaw) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value),
      _ => null,
    };

    final preset = IssueTargetPreset(
      issueTarget: issueTarget,
      vehiclePlate: vehiclePlate != null && vehiclePlate.isNotEmpty ? vehiclePlate : null,
      driverId: driverId,
      driverName: driverName != null && driverName.isNotEmpty ? driverName : null,
    );

    return preset.hasReusableTarget ? preset : null;
  }
}