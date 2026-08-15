class MapStyle {
  const MapStyle._();

  // 구글 맵 앱 블루 계열 다크 스타일
  static const String dark = '''
  [
    {
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#182A43"
        }
      ]
    },

    {
      "featureType": "landscape",
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#182A43"
        }
      ]
    },

    {
      "featureType": "landscape.man_made",
      "elementType": "geometry",
      "stylers": [
        {
          "visibility": "on"
        },
        {
          "color": "#294A78"
        }
      ]
    },

    {
      "featureType": "landscape.man_made",
      "elementType": "geometry.stroke",
      "stylers": [
        {
          "visibility": "on"
        },
        {
          "color": "#355D91"
        }
      ]
    },

    {
      "featureType": "poi",
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#203754"
        }
      ]
    },

    {
      "featureType": "poi",
      "elementType": "labels.text.fill",
      "stylers": [
        {
          "color": "#B8CBE0"
        }
      ]
    },

    {
      "featureType": "road",
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#607F9F"
        }
      ]
    },

    {
      "featureType": "road",
      "elementType": "geometry.stroke",
      "stylers": [
        {
          "color": "#17283E"
        }
      ]
    },

    {
      "featureType": "road",
      "elementType": "labels.text.fill",
      "stylers": [
        {
          "color": "#EEF4FC"
        }
      ]
    },

    {
      "featureType": "road.local",
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#557494"
        }
      ]
    },

    {
      "featureType": "road.highway",
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#7390AE"
        }
      ]
    },

    {
      "featureType": "water",
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#10243C"
        }
      ]
    },

    {
      "elementType": "labels.text.fill",
      "stylers": [
        {
          "color": "#DDE7F3"
        }
      ]
    },

    {
      "elementType": "labels.text.stroke",
      "stylers": [
        {
          "color": "#182A43"
        }
      ]
    }
  ]
  ''';
}
