import 'package:equatable/equatable.dart';

class Advs extends Equatable {
  const Advs({
    required this.id,
    required this.type,
    required this.timeOutInSeconds,
    required this.isLandscape,
    this.title,
    this.description,
    this.advData,
    this.referencesData,
    this.startDate,
    this.endDate,
    this.visibilityCount,
  });

  final String id;
  final String? title;
  final String? description;
  final int type;
  final String? advData;
  final String? referencesData;
  final String? startDate;
  final String? endDate;
  final int timeOutInSeconds;
  final int? visibilityCount;
  final bool isLandscape;

  @override
  List<Object?> get props => [id];
}
