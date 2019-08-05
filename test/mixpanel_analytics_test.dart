import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Client, Response;
import 'package:mixpanel_analytics/mixpanel_analytics.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHttpProvider extends Mock implements Client {}

class MockSharedPreferences extends Mock implements SharedPreferences {}

const String mixpanelToken = 'some-mixpanel-token';

const String userId = 'some-user-id';

const String fixedTimeString = '2019-06-21T15:16:22.328896';

const Map<String, String> fakeResponseNoVerbose = {'ok': '1', 'nook': '0'};

const String fakeNoOkResponseNoVerbose = '0';

void main() {
  MockHttpProvider http;
  MockSharedPreferences prefs;
  MixpanelAnalytics sut;
  StreamController<String> userId$;

  void stubPrefsSetString(String value) {
    when(prefs.setString('mixpanel.analytics', any))
        .thenAnswer((_) async => true);
  }

  void stubPrefsGetString(String value) {
    when(prefs.getString('mixpanel.analytics')).thenReturn(value);
  }

  String base64Encoder(Object event) {
    var str = json.encode(event);
    var bytes = utf8.encode(str);
    var base64 = base64Encode(bytes);
    return base64;
  }

  String buildGetRequest(String operation, Object event) =>
      '${MixpanelAnalytics.baseApi}/$operation/?data=${base64Encoder(event)}&verbose=0';

  void stubGet(Response response) {
    when(http.get(argThat(startsWith(MixpanelAnalytics.baseApi)),
            headers: anyNamed('headers')))
        .thenAnswer((_) async => response);
  }

  void stubPost(Response response) {
    when(http.post(argThat(startsWith(MixpanelAnalytics.baseApi)),
            headers: anyNamed('headers'), body: anyNamed('body')))
        .thenAnswer((_) async => response);
  }

  group('MixpanelAnalytics', () {
    setUp(() {
      userId$ = StreamController<String>();
      http = MockHttpProvider();
      sut = MixpanelAnalytics(
          token: mixpanelToken,
          userId$: userId$.stream,
          verbose: false,
          onError: (_) {})
        ..http = http;
      userId$.add(userId);
    });

    tearDown(() {
      userId$.close();
      http.close();
      clearInteractions(http);
      reset(http);
      http = null;
      sut = null;
    });

    test(
        '.track() sends an event to mixpanel with proper syntax using REST API',
        () async {
      stubGet(Response(fakeResponseNoVerbose['ok'], 200));

      var expected = buildGetRequest('track', {
        'event': 'random event',
        'properties': {
          'key': 'value',
          'token': 'some-mixpanel-token',
          'time': 1561122982328,
          'distinct_id': 'some-user-id'
        }
      });

      var success = await sut.track(
          event: 'random event',
          properties: {'key': 'value'},
          time: DateTime.parse(fixedTimeString));

      expect(success, true);

      expect(
          verify(http.get(captureAny, headers: anyNamed('headers')))
              .captured
              .single,
          expected);
    });

    test(
        '.engage() sends an event to mixpanel with proper syntax using REST API',
        () async {
      stubGet(Response(fakeResponseNoVerbose['ok'], 200));

      var expected = buildGetRequest('engage', {
        '\$set': {'key': 'value'},
        '\$token': 'some-mixpanel-token',
        '\$time': 1561122982328,
        '\$distinct_id': 'some-user-id'
      });

      var success = await sut.engage(
          operation: MixpanelUpdateOperations.$set,
          value: {'key': 'value'},
          time: DateTime.parse(fixedTimeString));

      expect(success, true);

      expect(
          verify(http.get(captureAny, headers: anyNamed('headers')))
              .captured
              .single,
          expected);
    });

    test('an unsuccessful request returns false', () async {
      stubGet(Response(fakeResponseNoVerbose['nook'], 401));

      var success = await sut.track(
          event: 'random event',
          properties: {'key': 'value'},
          time: DateTime.parse(fixedTimeString));

      expect(success, false);
    });
  });

  group('MixpanelAnalytics batch', () {
    int uploadIntervalSeconds = 1;

    setUp(() {
      userId$ = StreamController<String>();
      prefs = MockSharedPreferences();
      http = MockHttpProvider();
      sut = MixpanelAnalytics.batch(
          token: mixpanelToken,
          userId$: userId$.stream,
          uploadInterval: Duration(seconds: uploadIntervalSeconds),
          verbose: false,
          onError: (_) {})
        ..http = http
        ..prefs = prefs;
      userId$.add(userId);
    });

    tearDown(() {
      userId$.close();
      http.close();
      sut.dispose();
      clearInteractions(prefs);
      clearInteractions(http);
      reset(http);
      reset(prefs);
      prefs = null;
      http = null;
      sut = null;
    });

    test(
        '.track() sends a bunch of events in batch to mixpanel with proper syntax using REST API after X seconds',
        () async {
      stubPrefsSetString('');

      stubPost(Response(fakeResponseNoVerbose['ok'], 200));

      var expected = {
        'data': base64Encoder([
          {
            'event': 'random event',
            'properties': {
              'key': 'value1',
              'token': 'some-mixpanel-token',
              'time': 1561122982328,
              'distinct_id': 'some-user-id'
            }
          },
          {
            'event': 'random event',
            'properties': {
              'key': 'value2',
              'token': 'some-mixpanel-token',
              'time': 1561122982328,
              'distinct_id': 'some-user-id'
            }
          },
        ])
      };

      var success = await Future.wait(['value1', 'value2'].map((v) => sut.track(
          event: 'random event',
          properties: {'key': v},
          time: DateTime.parse(fixedTimeString))));

      expect(success, [true, true]);

      verifyZeroInteractions(http);

      await Future.delayed(Duration(seconds: uploadIntervalSeconds + 1), () {});

      expect(
          verify(http.post(any,
                  headers: anyNamed('headers'), body: captureAnyNamed('body')))
              .captured
              .single,
          expected);
    });

    test('batch mode will send whatever is in shared preferences on start',
        () async {
      var events = {
        'track': [
          {
            'event': 'random event',
            'properties': {
              'key': 'value1',
              'token': 'some-mixpanel-token',
              'time': 1561122982328,
              'distinct_id': 'some-user-id'
            }
          },
          {
            'event': 'random event',
            'properties': {
              'key': 'value2',
              'token': 'some-mixpanel-token',
              'time': 1561122982328,
              'distinct_id': 'some-user-id'
            }
          },
        ]
      };

      stubPrefsSetString('');

      stubPrefsGetString(json.encode(events));

      stubPost(Response(fakeResponseNoVerbose['ok'], 200));

      verifyZeroInteractions(http);

      var expected = {
        'data': base64Encoder([...events['track']])
      };

      await Future.delayed(Duration(seconds: uploadIntervalSeconds + 1), () {});

      expect(
          verify(http.post(any,
                  headers: anyNamed('headers'), body: captureAnyNamed('body')))
              .captured
              .single,
          expected);
    });
  });
}
