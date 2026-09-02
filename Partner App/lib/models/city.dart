class City {
  final String id;
  final String name;
  final String? state;

  City({
    required this.id,
    required this.name,
    this.state,
  });

  factory City.fromJson(Map<String, dynamic> json) {
    return City(
      id: json['id'],
      name: json['name'],
      state: json['state'],
    );
  }
}
