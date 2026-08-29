class SocialAccountStatusResponse {
  final List<String> linkedProviders;

  const SocialAccountStatusResponse({required this.linkedProviders});

  factory SocialAccountStatusResponse.fromJson(Map<String, dynamic> json) {
    final providers = json['linkedProviders'];

    return SocialAccountStatusResponse(
      linkedProviders: providers is List
          ? providers.whereType<String>().toList(growable: false)
          : const [],
    );
  }

  // 해당 플랫폼이 현재 계정에 연동되어 있는지 확인한다.
  bool isLinked(String provider) {
    return linkedProviders.contains(provider.toUpperCase());
  }
}