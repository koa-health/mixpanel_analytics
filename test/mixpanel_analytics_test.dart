import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Client, Response;
import 'package:mixpanel_analytics/mixpanel_analytics.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mixpanel_analytics_test.mocks.dart';

const String mixpanelToken = 'some-mixpanel-token';

const String userId = 'some-user-id';

const String fixedTimeString = '2019-06-21T15:16:22.32Z';

const Map<String, String> fakeResponseNoVerbose = {'ok': '1', 'nook': '0'};

const String fakeNoOkResponseNoVerbose = '0';

@GenerateMocks([Client, SharedPreferences])
void main() {
  late MockClient http;
  late MockSharedPreferences prefs;
  late MixpanelAnalytics sut;
  late StreamController<String> userId$;

  void stubPrefsSetString() {
    when(prefs.setString('mixpanel.analytics', any)).thenAnswer((_) async => true);
  }

  void stubPrefsGetString(String? value) {
    when(prefs.getString('mixpanel.analytics')).thenReturn(value);
  }

  String base64Encoder(Object event) {
    final str = json.encode(event);
    final bytes = utf8.encode(str);
    final base64 = base64Encode(bytes);
    return base64;
  }

  Uri buildGetRequest(String operation, Object event, {String? customUrl}) =>
      Uri.parse('${customUrl ?? MixpanelAnalytics.baseApi}/$operation/?data=${base64Encoder(event)}&verbose=0&ip=0');

  void stubGet(Response response) {
    when(http.get(any, headers: anyNamed('headers'))).thenAnswer((_) async => response);
  }

  void stubPost(Response response) {
    when(
      http.post(any, headers: anyNamed('headers'), body: anyNamed('body')),
    ).thenAnswer((_) async => response);
  }

  group('MixpanelAnalytics /', () {
    setUp(() {
      userId$ = StreamController<String>();
      http = MockClient();
      sut = MixpanelAnalytics(
        token: mixpanelToken,
        userId$: userId$.stream,
        verbose: false,
        useIp: false,
        onError: (_) {},
      )..http = http;
      userId$.add(userId);
    });

    tearDown(() {
      userId$.close();
      sut.dispose();
    });

    test('.track() sends an event to mixpanel with proper syntax using REST API', () async {
      stubGet(Response(fakeResponseNoVerbose['ok']!, 200));

      final expected = buildGetRequest('track', {
        'event': 'random event',
        'properties': {
          'key': 'value',
          'token': 'some-mixpanel-token',
          'time': 1561130182320,
          'distinct_id': 'some-user-id',
        },
      });

      final success = await sut.track(
        event: 'random event',
        properties: {'key': 'value'},
        time: DateTime.parse(fixedTimeString),
      );

      expect(success, true);

      expect(
        verify(http.get(captureAny, headers: anyNamed('headers'))).captured.single,
        expected,
      );
    });

    test('.engage() sends an event to mixpanel with proper syntax using REST API', () async {
      stubGet(Response(fakeResponseNoVerbose['ok']!, 200));

      final expected = buildGetRequest('engage', {
        '\$set': {'key': 'value'},
        '\$token': 'some-mixpanel-token',
        '\$time': 1561130182320,
        '\$distinct_id': 'some-user-id',
      });

      final success = await sut.engage(
        operation: MixpanelUpdateOperations.$set,
        value: {'key': 'value'},
        time: DateTime.parse(fixedTimeString),
      );

      expect(success, true);

      expect(
        verify(http.get(captureAny, headers: anyNamed('headers'))).captured.single,
        expected,
      );
    });

    test('an unsuccessful request returns false', () async {
      stubGet(Response(fakeResponseNoVerbose['nook']!, 401));

      final success = await sut.track(
        event: 'random event',
        properties: {'key': 'value'},
        time: DateTime.parse(fixedTimeString),
      );

      expect(success, false);
    });
  });

  group('MixpanelAnalytics batch /', () {
    int uploadIntervalSeconds = 1;

    setUp(() {
      userId$ = StreamController<String>();
      prefs = MockSharedPreferences();
      http = MockClient();
      sut = MixpanelAnalytics.batch(
        token: mixpanelToken,
        userId$: userId$.stream,
        uploadInterval: Duration(seconds: uploadIntervalSeconds),
        verbose: false,
        useIp: false,
        onError: (_) {},
      )
        ..http = http
        ..prefs = prefs;
      userId$.add(userId);
    });

    tearDown(() {
      userId$.close();
      sut.dispose();
    });

    test('.track() sends a bunch of events in batch to mixpanel with proper syntax using REST API after X seconds',
        () async {
      stubPrefsSetString();
      stubPrefsGetString(null);

      stubPost(Response(fakeResponseNoVerbose['ok']!, 200));

      final expected = {
        'data': base64Encoder([
          {
            'event': 'random event',
            'properties': {
              'key': 'value1',
              'token': 'some-mixpanel-token',
              'time': 1561130182320,
              'distinct_id': 'some-user-id',
            }
          },
          {
            'event': 'random event',
            'properties': {
              'key': 'value2',
              'token': 'some-mixpanel-token',
              'time': 1561130182320,
              'distinct_id': 'some-user-id',
            },
          },
        ])
      };

      final success = await Future.wait(
        ['value1', 'value2'].map(
          (v) => sut.track(event: 'random event', properties: {'key': v}, time: DateTime.parse(fixedTimeString)),
        ),
      );

      expect(success, [true, true]);

      verifyZeroInteractions(http);

      await Future.delayed(Duration(seconds: uploadIntervalSeconds + 1), () {});

      expect(
        verify(http.post(any, headers: anyNamed('headers'), body: captureAnyNamed('body'))).captured.single,
        expected,
      );
    });

    test('batch mode will send whatever is in shared preferences whenever an event is sent', () async {
      final events = {
        'track': [
          {
            'event': 'random event',
            'properties': {
              'key': 'value1',
              'token': 'some-mixpanel-token',
              'time': 1561130182320,
              'distinct_id': 'some-user-id'
            }
          },
          {
            'event': 'random event',
            'properties': {
              'key': 'value2',
              'token': 'some-mixpanel-token',
              'time': 1561130182320,
              'distinct_id': 'some-user-id'
            },
          },
        ]
      };

      final extraEvent = {
        'event': 'random event',
        'properties': {
          'key': 'value3',
          'token': 'some-mixpanel-token',
          'time': 1561130182320,
          'distinct_id': 'some-user-id'
        },
      };

      stubPrefsSetString();

      stubPrefsGetString(json.encode(events));

      stubPost(Response(fakeResponseNoVerbose['ok']!, 200));

      verifyZeroInteractions(http);

      await sut.track(
        // ignore: avoid_as
        event: extraEvent['event'] as String,
        // ignore: avoid_as
        properties: extraEvent['properties'] as Map<String, dynamic>,
        time: DateTime.fromMillisecondsSinceEpoch(1561130182320),
      );

      final expected = {
        'data': base64Encoder([...events['track']!, extraEvent]),
      };

      await Future.delayed(Duration(seconds: uploadIntervalSeconds + 2), () {});

      expect(
        verify(http.post(any, headers: anyNamed('headers'), body: captureAnyNamed('body'))).captured.single,
        expected,
      );
    });
  });

  group('Custom Endpoint /', () {
    setUp(() {
      userId$ = StreamController<String>();
      http = MockClient();
      sut = MixpanelAnalytics(
        token: mixpanelToken,
        userId$: userId$.stream,
        verbose: false,
        useIp: false,
        onError: (_) {},
        customApi: 'https://api-eu.mixpanel.com',
      )..http = http;
      userId$.add(userId);
    });

    tearDown(() {
      userId$.close();
      sut.dispose();
    });

    test('.track() uses custom endpoint if supplied', () async {
      // arrange
      stubGet(Response(fakeResponseNoVerbose['ok']!, 200));

      final expected = buildGetRequest(
        'track',
        {
          'event': 'random event',
          'properties': {
            'key': 'value',
            'token': 'some-mixpanel-token',
            'time': 1561130182320,
            'distinct_id': 'some-user-id',
          },
        },
        customUrl: 'https://api-eu.mixpanel.com',
      );

      // act
      final success = await sut.track(
        event: 'random event',
        properties: {'key': 'value'},
        time: DateTime.parse(fixedTimeString),
      );

      // assert
      expect(success, true);

      verify(http.get(expected, headers: anyNamed('headers')));
    });

    test('.engage() uses custom endpoint if supplied', () async {
      // arrange
      stubGet(Response(fakeResponseNoVerbose['ok']!, 200));

      final expected = buildGetRequest(
        'engage',
        {
          '\$set': {'key': 'value'},
          '\$token': 'some-mixpanel-token',
          '\$time': 1561130182320,
          '\$distinct_id': 'some-user-id',
        },
        customUrl: 'https://api-eu.mixpanel.com',
      );

      // act
      final success = await sut.engage(
        operation: MixpanelUpdateOperations.$set,
        value: {'key': 'value'},
        time: DateTime.parse(fixedTimeString),
      );

      // assert
      expect(success, true);

      verify(http.get(expected, headers: anyNamed('headers')));
    });
  });
}
