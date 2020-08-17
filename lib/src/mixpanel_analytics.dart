import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MixpanelUpdateOperations {
  $set,
  $setOnce,
  $add,
  $append,
  $union,
  $remove,
  $unset,
  $delete
}

typedef ShaFn = String Function(String value);

class MixpanelAnalytics {
  /// This are the update operations allowed for the 'engage' request.
  static const Map<MixpanelUpdateOperations, String> updateOperations = {
    MixpanelUpdateOperations.$set: '\$set',
    MixpanelUpdateOperations.$setOnce: '\$set_once',
    MixpanelUpdateOperations.$add: '\$add',
    MixpanelUpdateOperations.$append: '\$append',
    MixpanelUpdateOperations.$union: '\$union',
    MixpanelUpdateOperations.$remove: '\$remove',
    MixpanelUpdateOperations.$unset: '\$unset',
    MixpanelUpdateOperations.$delete: '\$delete',
  };

  // The Mixpanel token associated with your project.
  String _token;

  // If present and equal to true, more detailed information will be printed on error.
  bool _verbose;

  /// If present and equal to true, the geolocation data (e.g. city & country)
  /// will be included and inferred from client's IP address.
  bool _ip;

  // In case we use [MixpanelAnalytics.batch()] we will send analytics every [uploadInterval]
  // Will be zero by default
  Duration _uploadInterval = Duration.zero;

  // In case we use [MixpanelAnalytics.batch()] we need to provide a storage provider
  // This will be used to save the events not sent
  @visibleForTesting
  SharedPreferences prefs;

  // If exists, will be sent in the event, otherwise anonymousId will be used.
  Stream<String> _userId$;

  // Stores the value of the userId
  String _userId;

  /// Reference to the timer set to upload events in batch
  Timer _batchTimer;

  /// If true, sensitive information like deviceId or userId will be anonymized prior to being sent.
  bool _shouldAnonymize;

  /// As the fields to be anonymized will be the same with every event log, we can keep a cache of the values already anonymized.
  Map<String, String> _anonymized;

  /// Function used to anonymize the data.
  ShaFn _shaFn;

  // If this is not null, any error will be sent to this function, otherwise `debugPrint` will be used.
  void Function(Object error) _onError;

  // Queued events used when these are sent in batch.
  final Map<String, dynamic> _queuedEvents = {'track': [], 'engage': []};

  List<dynamic> get _trackEvents => _queuedEvents['track'];

  List<dynamic> get _engageEvents => _queuedEvents['engage'];

  // This is false when start and true once the events are restored from storage.
  bool _isQueuedEventsReadFromStorage = false;

  static const int maxEventsInBatchRequest = 50;

  /// We can inject the client required, useful for testing
  Client http = Client();

  static const String baseApi = 'https://api.mixpanel.com';

  static const _prefsKey = 'mixpanel.analytics';

  /// Returns the value of the token in mixpanel.
  String get mixpanelToken => _token;

  /// When in batch mode, events will be added to a queue and send in batch every [_uploadInterval]
  bool get isBatchMode => _uploadInterval.compareTo(Duration.zero) != 0;

  /// Default sha function to be used when none is provided.
  static String _defaultShaFn(value) => value;

  /// Used in case we want to remove the timer to send batched events.
  void dispose() {
    if (_batchTimer != null) {
      _batchTimer.cancel();
      _batchTimer = null;
    }
  }

  /// Provides an instance of this class.
  /// The instance of the class created with this constructor will send the events on the fly, which could result on high traffic in case there are many events.
  /// Also, if a request returns an error, this will be logged but the event will be lost.
  /// If you want events to be send in batch and also reliability to the requests use [MixpanelAnalytics.batch] instead.
  /// [token] is the Mixpanel token associated with your project.
  /// [userId$] is a stream which contains the value of the userId that will be used to identify the events for a user.
  /// [shouldAnonymize] will anonymize the sensitive information (userId) sent to mixpanel.
  /// [shaFn] function used to anonymize the data.
  /// [verbose] true will provide a detailed error cause in case the request is not successful.
  /// [ip] is the `ip` property as explained in [mixpanel documentation](https://developer.mixpanel.com/docs/http)
  /// [onError] is a callback function that will be executed in case there is an error, otherwise `debugPrint` will be used.
  MixpanelAnalytics({
    @required String token,
    @required Stream<String> userId$,
    bool shouldAnonymize,
    ShaFn shaFn,
    bool verbose,
    bool ip,
    Function onError,
  }) {
    _token = token;
    _userId$ = userId$;
    _verbose = verbose;
    _ip = ip;
    _onError = onError;
    _shouldAnonymize = shouldAnonymize ?? false;
    _shaFn = shaFn ?? _defaultShaFn;

    _userId$?.listen((id) => _userId = id);
  }

  /// Provides an instance of this class.
  /// With this constructor, the instance will send the events in batch, and also if the request can't be sent (connectivity issues) it will be retried until it is successful.
  /// [token] is the Mixpanel token associated with your project.
  /// [userId$] is a stream which contains the value of the userId that will be used to identify the events for a user.
  /// [uploadInterval] is the interval used to batch the events.
  /// [shouldAnonymize] will anonymize the sensitive information (userId) sent to mixpanel.
  /// [shaFn] function used to anonymize the data.
  /// [verbose] true will provide a detailed error cause in case the request is not successful.
  /// [ip] is the `ip` property as explained in [mixpanel documentation](https://developer.mixpanel.com/docs/http)
  /// [onError] is a callback function that will be executed in case there is an error, otherwise `debugPrint` will be used.
  MixpanelAnalytics.batch({
    @required String token,
    @required Stream<String> userId$,
    @required Duration uploadInterval,
    bool shouldAnonymize,
    ShaFn shaFn,
    bool verbose,
    bool ip,
    Function onError,
  }) {
    _token = token;
    _userId$ = userId$;
    _verbose = verbose;
    _ip = ip;
    _uploadInterval = uploadInterval;
    _shouldAnonymize = shouldAnonymize ?? false;
    _shaFn = shaFn ?? _defaultShaFn;

    _onError = onError;

    _batchTimer = Timer.periodic(_uploadInterval, (_) => _uploadQueuedEvents());

    _userId$?.listen((id) => _userId = id);
  }

  /// Sends a request to track a specific event.
  /// Requests will be sent immediately. If you want to batch the events use [MixpanelAnalytics.batch] instead.
  /// [event] will be the name of the event.
  /// [properties] is a map with the properties to be sent.
  /// [time] is the date that will be added in the event. If not provided, current time will be used.
  /// [insertId] is the `$insert_id` property as explained in [mixpanel documentation](https://developer.mixpanel.com/docs/http)
  Future<bool> track({
    @required String event,
    @required Map<String, dynamic> properties,
    DateTime time,
    String ip,
    String insertId,
  }) async {
    if (event == null) {
      throw ArgumentError.notNull('event');
    }
    if (properties == null) {
      throw ArgumentError.notNull('properties');
    }

    var trackEvent = _createTrackEvent(
        event, properties, time ?? DateTime.now(), ip, insertId);

    if (isBatchMode) {
      _trackEvents.add(trackEvent);
      return _saveQueuedEventsToLocalStorage();
    }

    var base64Event = _base64Encoder(trackEvent);
    return _sendTrackEvent(base64Event);
  }

  /// Sends a request to engage a specific event.
  /// Requests will be sent immediately. If you want to batch the events use [MixpanelAnalytics.batch] instead.
  /// [operation] is the operation update as per [MixpanelUpdateOperations].
  /// [value] is a map with the properties to be sent.
  /// [time] is the date that will be added in the event. If not provided, current time will be used.
  /// [ignoreTime] is the `$ignore_time` property as explained in [mixpanel documentation](https://developer.mixpanel.com/docs/http)
  /// [ignoreAlias] is the `$ignore_alias` property as explained in [mixpanel documentation](https://developer.mixpanel.com/docs/http)
  Future<bool> engage({
    @required MixpanelUpdateOperations operation,
    @required Map<String, dynamic> value,
    DateTime time,
    String ip,
    bool ignoreTime,
    bool ignoreAlias,
  }) async {
    if (operation == null) {
      throw ArgumentError.notNull('operation');
    }
    if (value == null) {
      throw ArgumentError.notNull('value');
    }

    var engageEvent = _createEngageEvent(
        operation, value, time ?? DateTime.now(), ip, ignoreTime, ignoreAlias);

    if (isBatchMode) {
      _engageEvents.add(engageEvent);
      return _saveQueuedEventsToLocalStorage();
    }

    var base64Event = _base64Encoder(engageEvent);
    return _sendEngageEvent(base64Event);
  }

  // Reads queued events from the storage when we are in batch mode.
  // We do this in case the app was closed with events pending to be sent.
  Future<void> _restoreQueuedEventsFromStorage() async {
    prefs ??= await SharedPreferences.getInstance();
    var encoded = prefs.getString(_prefsKey);
    if (encoded != null) {
      Map<String, dynamic> events = json.decode(encoded);
      _queuedEvents.addAll(events);
    }
  }

  // If we are in batch mode we save all events in storage in case the app is closed.
  Future<bool> _saveQueuedEventsToLocalStorage() async {
    prefs ??= await SharedPreferences.getInstance();
    var encoded = json.encode(_queuedEvents);
    var result = await prefs.setString(_prefsKey, encoded).catchError((error) {
      _onErrorHandler(error, 'Error saving events in storage');
      return false;
    });
    return result;
  }

  // Tries to send all events pending to be send.
  // TODO if error when sending, send events in isolation identify the incorrect message
  Future<void> _uploadQueuedEvents() async {
    if (!_isQueuedEventsReadFromStorage) {
      await _restoreQueuedEventsFromStorage();
      _isQueuedEventsReadFromStorage = true;
    }
    await _uploadEvents(_trackEvents, _sendTrackBatch);
    await _uploadEvents(_engageEvents, _sendEngageBatch);
    await _saveQueuedEventsToLocalStorage();
  }

  // As the API for Mixpanel only allows 50 events per batch, we need to restrict the events sent on each request.
  int _getMaximumRange(int length) =>
      length < maxEventsInBatchRequest ? length : maxEventsInBatchRequest;

  // Uploads all pending events in batches of maximum [maxEventsInBatchRequest].
  Future<void> _uploadEvents(List<dynamic> events, Function sendFn) async {
    List<dynamic> unsentEvents = [];
    while (events.isNotEmpty) {
      var maxRange = _getMaximumRange(events.length);
      var range = events.getRange(0, maxRange).toList();
      var batch = _base64Encoder(range);
      var success = await sendFn(batch);
      if (!success) {
        unsentEvents.addAll(range);
      }
      events.removeRange(0, maxRange);
    }
    if (unsentEvents.isNotEmpty) {
      events.addAll(unsentEvents);
    }
  }

  // The track event is coded into base64 with the required properties.
  Map<String, dynamic> _createTrackEvent(
    String event,
    Map<String, dynamic> props,
    DateTime time,
    String ip,
    String insertId,
  ) {
    var properties = {
      ...props,
      'token': _token,
      'time': time.millisecondsSinceEpoch,
      'distinct_id': props['distinct_id'] == null
          ? _userId == null
              ? 'Unknown'
              : _shouldAnonymize ? _anonymize('userId', _userId) : _userId
          : props['distinct_id']
    };
    if (ip != null) {
      properties = {...properties, 'ip': ip};
    }
    if (insertId != null) {
      properties = {...properties, '\$insert_id': insertId};
    }
    var data = {'event': event, 'properties': properties};
    return data;
  }

  // The engage event is coded into base64 with the required properties.
  Map<String, dynamic> _createEngageEvent(
      MixpanelUpdateOperations operation,
      Map<String, dynamic> value,
      DateTime time,
      String ip,
      bool ignoreTime,
      bool ignoreAlias) {
    var data = {
      updateOperations[operation]: value,
      '\$token': _token,
      '\$time': time.millisecondsSinceEpoch,
      '\$distinct_id': value['distinct_id'] == null
          ? _userId == null
              ? 'Unknown'
              : _shouldAnonymize ? _anonymize('userId', _userId) : _userId
          : value['distinct_id']
    };
    if (ip != null) {
      data = {...data, '\$ip': ip};
    }
    if (ignoreTime != null) {
      data = {...data, '\$ignore_time': ignoreTime};
    }
    if (ignoreAlias != null) {
      data = {...data, '\$ignore_alias': ignoreAlias};
    }
    return data;
  }

  // Event data has to be sent with base64 encoding.
  String _base64Encoder(Object event) {
    var str = json.encode(event);
    var bytes = utf8.encode(str);
    var base64 = base64Encode(bytes);
    return base64;
  }

  Future<bool> _sendTrackEvent(String event) => _sendEvent(event, 'track');

  Future<bool> _sendEngageEvent(String event) => _sendEvent(event, 'engage');

  // Sends the event to the mixpanel API endpoint.
  Future<bool> _sendEvent(String event, String op) async {
    var url = '$baseApi/$op/?data=$event&verbose=${_verbose ? 1 : 0}'
        '&ip=${_ip ? 1 : 0}';
    try {
      var response = await http.get(url, headers: {
        'Content-type': 'application/json',
      });
      return response.statusCode == 200 &&
          _validateResponseBody(url, response.body);
    } on Exception catch (error) {
      _onErrorHandler(error, 'Request error to $url');
      return false;
    }
  }

  Future<bool> _sendTrackBatch(String event) => _sendBatch(event, 'track');

  Future<bool> _sendEngageBatch(String event) => _sendBatch(event, 'engage');

  // Sends the batch of events to the mixpanel API endpoint.
  Future<bool> _sendBatch(String batch, String op) async {
    var url = '$baseApi/$op/?verbose=${_verbose ? 1 : 0}&ip=${_ip ? 1 : 0}';
    try {
      var response = await http.post(url, headers: {
        'Content-type': 'application/x-www-form-urlencoded',
      }, body: {
        'data': batch
      });
      return response.statusCode == 200 &&
          _validateResponseBody(url, response.body);
    } on Exception catch (error) {
      _onErrorHandler(error, 'Request error to $url');
      return false;
    }
  }

  // Depending on the value of [verbose], this will validate the body and handle the error.
  // Check [mixpanel documentation](https://developer.mixpanel.com/docs/http) for more information on `verbose`.
  bool _validateResponseBody(String url, String body) {
    if (_verbose) {
      var decodedBody = json.decode(body);
      var status = decodedBody['status'];
      var error = decodedBody['error'];
      if (status == 0) {
        _onErrorHandler(null, 'Request error to $url: $error');
        return false;
      }
      return true;
    }
    // no verbose
    if (body == '0') {
      _onErrorHandler(null, 'Request error to $url');
      return false;
    }
    return true;
  }

  // Anonymizes the field but also saves it in a local cache.
  String _anonymize(String field, String value) {
    _anonymized ??= {};
    if (_anonymized[field] == null) {
      _anonymized[field] = _shaFn(value);
    }
    return _anonymized[field];
  }

  // Proxies the error to the callback function provided or to standard `debugPrint`.
  void _onErrorHandler(dynamic error, String message) {
    if (_onError != null) {
      _onError(error ?? message);
    } else {
      debugPrint(message);
    }
  }
}
