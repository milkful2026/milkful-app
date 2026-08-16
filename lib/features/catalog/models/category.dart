import 'package:equatable/equatable.dart';

/// MA-115 §7. `iconName` maps to a Material [Icon] at render time — no
/// custom art asset pipeline, matching how the rest of this app's screens
/// use plain icons rather than image assets.
class Category extends Equatable {
  const Category({required this.id, required this.name, this.iconName});

  final String id;
  final String name;
  final String? iconName;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        iconName: json['iconName'] as String?,
      );

  @override
  List<Object?> get props => [id, name, iconName];
}
