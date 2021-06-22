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
  $delete,
}

typedef ShaFn = String Function(String value);

class MixpanelAnalytics {
  /// The Mixpanel token associated with your project.
  final String _token;

  /// If present and equal to true, more detailed information will be printed on error.
  final bool _verbose;

  /// If present and equal to true, the geolocation data (e.g. city & country)
  /// will be included and inferred from client's IP address.
  final bool _useIp;

  /// In case we use [MixpanelAnalytics.batch()] we will send analytics every [uploadInterval]
  /// Will be zero by default
  Duration _uploadInterval = Duration.zero;

  /// In case we use [MixpanelAnalytics.batch()] we need to provide a storage provider
  /// This will be used to save the events not sent
  @visibleForTesting
  SharedPreferences? prefs;

  /// If exists, will be sent in the event, otherwise anonymousId will be used.
  final Stream<String?>? _userId$;

  /// Stores the value of the userId
  String? _userId;

  /// Sets the value of the userId.
  set userId(String? id) => _userId = id;

  /// Sets the optional headers.
  set optionalHeaders(Map<String, String> optionalHeaders) =>
      _optionalHeaders = optionalHeaders;

  /// Reference to the timer set to upload events in batch
  Timer? _batchTimer;

  /// If true, sensitive information like deviceId or userId will be anonymized prior to being sent.
  final bool _shouldAnonymize;

  /// As the fields to be anonymized will be the same with every event log, we can keep a cache of the values already anonymized.
  Map<String, String>? _anonymized;

  /// Function used to anonymize the data.
  final ShaFn _shaFn;

  /// If this is not null, any error will be sent to this function, otherwise `debugPrint` will be used.
  final void Function(Object error)? _onError;

  /// Queued events used when these are sent in batch.
  final Map<String, dynamic> _queuedEvents = {'track': [], 'engage': []};

  List<dynamic> get _trackEvents => _queuedEvents['track'];

  List<dynamic> get _engageEvents => _queuedEvents['engage'];

  /// This is false when start and true once the events are restored from storage.
  bool _isQueuedEventsReadFromStorage = false;

  static const int maxEventsInBatchRequest = 50;

  /// We can inject the client required, useful for testing
  Client http = Client();

  static const String _baseUsApiUrl = 'https://api.mixpanel.com';

  static String _prefsKey = 'mixpanel.analytics';

  /// Returns the value of the token in mixpanel.
  String get mixpanelToken => _token;

  /// When in batch mode, events will be added to a queue and send in batch every [_uploadInterval]
  bool get isBatchMode => _uploadInterval.compareTo(Duration.zero) != 0;

  /// Default sha function to be used when none is provided.
  static String _defaultShaFn(value) => value;

  /// Proxy url to by pass CORs in flutter web
  final String? _proxyUrl;

  /// Optional headers to add to the requests to MixPanel.
  Map<String, String>? _optionalHeaders;

  /// By default will point to the US-based Mixpanel servers (api.mixpanel.com)
  /// Its value can be overriden in the constructor and there you can use, for instance,
  /// the EU-based servers url: api-eu.mixpanel.com
  /// See this for more information: https://developer.mixpanel.com/docs/privacy-security#storing-your-data-in-the-european-union
  final String baseApiUrl;

  /// Used in case we want to remove the timer to send batched events.
  void dispose() {
    _batchTimer?.cancel();
    _batchTimer = null;
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
  /// [useIp] is the `ip` property as explained in [mixpanel documentation](https://developer.mixpanel.com/docs/http)
  /// [onError] is a callback function that will be executed in case there is an error, otherwise `debugPrint` will be used.
  /// [proxyUrl] URL to use in the requests as a proxy. This URL will be used as follows $proxyUrl/mixpanel.api...
  /// [optionalHeaders] http headers to add in each request.
  /// [prefsKey] key to use in the SharedPreferences. If you leave it empty a default name will be used.
  /// [baseApiUrl] Ingestion API URL. If you don't inform it, the US-based url will be used (api.mixpanel.com). https://developer.mixpanel.com/docs/privacy-security#storing-your-data-in-the-european-union
  MixpanelAnalytics({
    required String token,
    Stream<String?>? userId$,
    bool shouldAnonymize = false,
    ShaFn shaFn = _defaultShaFn,
    bool verbose = false,
    bool useIp = false,
    void Function(Object)? onError,
    String? proxyUrl,
    Map<String, String>? optionalHeaders,
    String? prefsKey,
    String? baseApiUrl,
  })  : _token = token,
        _userId$ = userId$,
        _verbose = verbose,
        _useIp = useIp,
        _onError = onError,
        _shouldAnonymize = shouldAnonymize,
        _shaFn = shaFn,
        _proxyUrl = proxyUrl,
        _optionalHeaders = optionalHeaders,
        baseApiUrl = baseApiUrl ?? _baseUsApiUrl {
    _userId$?.listen((id) => _userId = id);
    _prefsKey = prefsKey ?? _prefsKey;
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
  /// [proxyUrl] URL to use in the requests as a proxy. This URL will be used as follows $proxyUrl/mixpanel.api...
  /// [optionalHeaders] http headers to add in each request.
  /// [prefsKey] key to use in the SharedPreferences. If you leave it empty a default name will be used.
  /// [baseApiUrl] Ingestion API URL. If you don't inform it, the US-based url will be used (api.mixpanel.com). https://developer.mixpanel.com/docs/privacy-security#storing-your-data-in-the-european-union
  MixpanelAnalytics.batch({
    required String token,
    required Duration uploadInterval,
    Stream<String?>? userId$,
    bool shouldAnonymize = false,
    ShaFn shaFn = _defaultShaFn,
    bool verbose = false,
    bool useIp = false,
    void Function(Object)? onError,
    String? proxyUrl,
    Map<String, String>? optionalHeaders,
    String? prefsKey,
    String? baseApiUrl,
  })  : _token = token,
        _userId$ = userId$,
        _verbose = verbose,
        _useIp = useIp,
        _onError = onError,
        _shouldAnonymize = shouldAnonymize,
        _shaFn = shaFn,
        _proxyUrl = proxyUrl,
        _uploadInterval = uploadInterval,
        _optionalHeaders = optionalHeaders,
        baseApiUrl = baseApiUrl ?? _baseUsApiUrl {
    _batchTimer = Timer.periodic(_uploadInterval, (_) => _uploadQueuedEvents());
    _userId$?.listen((id) => _userId = id);
    _prefsKey = prefsKey ?? _prefsKey;
  }

  /// Sends a request to track a specific event.
  /// Requests will be sent immediately. If you want to batch the events use [MixpanelAnalytics.batch] instead.
  /// [event] will be the name of the event.
  /// [properties] is a map with the properties to be sent.
  /// [time] is the date that will be added in the event. If not provided, current time will be used.
  /// [ip] is the `ip` property as explained in [mixpanel documentation](https://developer.mixpanel.com/docs/http)
  /// [insertId] is the `$insert_id` property as explained in [mixpanel documentation](https://developer.mixpanel.com/docs/http)
  Future<bool> track({
    required String event,
    required Map<String, dynamic> properties,
    DateTime? time,
    String? ip,
    String? insertId,
  }) async {
    final trackEvent = _createTrackEvent(
        event, properties, time ?? DateTime.now(), ip, insertId);

    if (isBatchMode) {
      // TODO: this should be place within an init() along within the constructor.
      // This is not perfect, as we are waiting for the caller to send an event before sending the stored in memory.
      // But doing it on an init() would be a breaking change.
      // To be executed only the first time user tries to send an event
      if (!_isQueuedEventsReadFromStorage) {
        await _restoreQueuedEventsFromStorage();
        _isQueuedEventsReadFromStorage = true;
      }
      _trackEvents.add(trackEvent);
      return _saveQueuedEventsToLocalStorage();
    }

    final base64Event = _base64Encoder(trackEvent);
    return _sendTrackEvent(base64Event);
  }

  /// Sends a request to engage a specific event.
  /// Requests will be sent immediately. If you want to batch the events use [MixpanelAnalytics.batch] instead.
  /// [operation] is the operation update as per [MixpanelUpdateOperations].
  /// [value] is a map with the properties to be sent.
  /// [time] is the date that will be added in the event. If not provided, current time will be used.
  /// [ip] is the `ip` property as explained in [mixpanel documentation](https://developer.mixpanel.com/docs/http)
  /// [ignoreTime] is the `$ignore_time` property as explained in [mixpanel documentation](https://developer.mixpanel.com/docs/http)
  /// [ignoreAlias] is the `$ignore_alias` property as explained in [mixpanel documentation](https://developer.mixpanel.com/docs/http)
  Future<bool> engage({
    required MixpanelUpdateOperations operation,
    required Map<String, dynamic> value,
    DateTime? time,
    String? ip,
    bool? ignoreTime,
    bool? ignoreAlias,
  }) async {
    final engageEvent = _createEngageEvent(
        operation, value, time ?? DateTime.now(), ip, ignoreTime, ignoreAlias);

    if (isBatchMode) {
      // TODO: this should be place within an init() along within the constructor.
      // This is not perfect, as we are waiting for the caller to send an event before sending the stored in memory.
      // But doing it on an init() would be a breaking change.
      // To be executed only the first time user tries to send an event
      if (!_isQueuedEventsReadFromStorage) {
        await _restoreQueuedEventsFromStorage();
        _isQueuedEventsReadFromStorage = true;
      }
      _engageEvents.add(engageEvent);
      return _saveQueuedEventsToLocalStorage();
    }

    final base64Event = _base64Encoder(engageEvent);
    return _sendEngageEvent(base64Event);
  }

  /// Reads queued events from the storage when we are in batch mode.
  /// We do this in case the app was closed with events pending to be sent.
  Future<void> _restoreQueuedEventsFromStorage() async {
    prefs ??= await SharedPreferences.getInstance();
    final encoded = prefs!.getString(_prefsKey);
    if (encoded != null) {
      Map<String, dynamic> events = json.decode(encoded);
      _queuedEvents.addAll(events);
    }
  }

  /// If we are in batch mode we save all events in storage in case the app is closed.
  Future<bool> _saveQueuedEventsToLocalStorage() async {
    prefs ??= await SharedPreferences.getInstance();
    final encoded = json.encode(_queuedEvents);
    final result =
        await prefs!.setString(_prefsKey, encoded).catchError((error) {
      _onErrorHandler(error, 'Error saving events in storage');
      return false;
    });
    return result;
  }

  /// Tries to send all events pending to be send.
  /// TODO: if error when sending, send events in isolation identify the incorrect message
  Future<void> _uploadQueuedEvents() async {
    await _uploadEvents(_trackEvents, _sendTrackBatch);
    await _uploadEvents(_engageEvents, _sendEngageBatch);
    await _saveQueuedEventsToLocalStorage();
  }

  /// As the API for Mixpanel only allows 50 events per batch, we need to restrict the events sent on each request.
  int _getMaximumRange(int length) =>
      length < maxEventsInBatchRequest ? length : maxEventsInBatchRequest;

  /// Uploads all pending events in batches of maximum [maxEventsInBatchRequest].
  Future<void> _uploadEvents(List<dynamic> events, Function sendFn) async {
    List<dynamic> unsentEvents = [];
    while (events.isNotEmpty) {
      final maxRange = _getMaximumRange(events.length);
      final range = events.getRange(0, maxRange).toList();
      final batch = _base64Encoder(range);
      final success = await sendFn(batch);
      if (!success) {
        unsentEvents.addAll(range);
      }
      events.removeRange(0, maxRange);
    }
    if (unsentEvents.isNotEmpty) {
      events.addAll(unsentEvents);
    }
  }

  /// The track event is coded into base64 with the required properties.
  Map<String, dynamic> _createTrackEvent(
    String event,
    Map<String, dynamic> props,
    DateTime time,
    String? ip,
    String? insertId,
  ) {
    var properties = {
      ...props,
      'token': _token,
      'time': time.millisecondsSinceEpoch,
      'distinct_id': props['distinct_id'] == null
          ? _userId == null
              ? 'Unknown'
              : _shouldAnonymize
                  ? _anonymize('userId', _userId!)
                  : _userId
          : props['distinct_id']
    };
    if (ip != null) {
      properties = {...properties, 'ip': ip};
    }
    if (insertId != null) {
      properties = {...properties, '\$insert_id': insertId};
    }
    final data = {'event': event, 'properties': properties};
    return data;
  }

  /// The engage event is coded into base64 with the required properties.
  Map<String, dynamic> _createEngageEvent(
    MixpanelUpdateOperations operation,
    Map<String, dynamic> value,
    DateTime time,
    String? ip,
    bool? ignoreTime,
    bool? ignoreAlias,
  ) {
    var data = <String, dynamic>{
      operation.propertyKey: value,
      '\$token': _token,
      '\$time': time.millisecondsSinceEpoch,
      '\$distinct_id': value['distinct_id'] == null
          ? _userId == null
              ? 'Unknown'
              : _shouldAnonymize
                  ? _anonymize('userId', _userId!)
                  : _userId
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

  /// Event data has to be sent with base64 encoding.
  String _base64Encoder(Object event) {
    final str = json.encode(event);
    final bytes = utf8.encode(str);
    final base64 = base64Encode(bytes);
    return base64;
  }

  Future<bool> _sendTrackEvent(String event) => _sendEvent(event, 'track');

  Future<bool> _sendEngageEvent(String event) => _sendEvent(event, 'engage');

  /// Sends the event to the mixpanel API endpoint.
  Future<bool> _sendEvent(String event, String op) async {
    var url = '$baseApiUrl/$op/?data=$event&verbose=${_verbose ? 1 : 0}'
        '&ip=${_useIp ? 1 : 0}';
    if (_proxyUrl != null) {
      url = url.replaceFirst('https://', '');
      url = '$_proxyUrl/$url';
    }

    try {
      final headers = <String, String>{};

      if (_optionalHeaders?.isNotEmpty ?? false) {
        headers.addAll(_optionalHeaders!);
      }

      final response = await http.get(Uri.parse(url), headers: headers);
      return response.statusCode == 200 &&
          _validateResponseBody(url, response.body);
    } on Exception catch (error) {
      _onErrorHandler(error, 'Request error to $url');
      return false;
    }
  }

  Future<bool> _sendTrackBatch(String event) => _sendBatch(event, 'track');

  Future<bool> _sendEngageBatch(String event) => _sendBatch(event, 'engage');

  /// Sends the batch of events to the mixpanel API endpoint.
  Future<bool> _sendBatch(String batch, String op) async {
    var url =
        '$baseApiUrl/$op/?verbose=${_verbose ? 1 : 0}&ip=${_useIp ? 1 : 0}';
    if (_proxyUrl != null) {
      url = url.replaceFirst('https://', '');
      url = '$_proxyUrl/$url';
    }
    try {
      var headers = {'Content-type': 'application/x-www-form-urlencoded'};

      if (_optionalHeaders?.isNotEmpty ?? false) {
        headers.addAll(_optionalHeaders!);
      }

      final response = await http
          .post(Uri.parse(url), headers: headers, body: {'data': batch});
      return response.statusCode == 200 &&
          _validateResponseBody(url, response.body);
    } on Exception catch (error) {
      _onErrorHandler(error, 'Request error to $url');
      return false;
    }
  }

  /// Depending on the value of [verbose], this will validate the body and handle the error.
  /// Check [mixpanel documentation](https://developer.mixpanel.com/docs/http) for more information on `verbose`.
  bool _validateResponseBody(String url, String body) {
    if (_verbose) {
      final decodedBody = json.decode(body);
      final status = decodedBody['status'];
      final error = decodedBody['error'];
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

  /// Anonymizes the field but also saves it in a local cache.
  String _anonymize(String field, String value) {
    _anonymized ??= {};
    if (_anonymized![field] == null) {
      _anonymized![field] = _shaFn(value);
    }
    return _anonymized![field]!;
  }

  /// Proxies the error to the callback function provided or to standard `debugPrint`.
  void _onErrorHandler(Object? error, String message) {
    final errorCallback = _onError;
    if (errorCallback != null) {
      errorCallback(error ?? message);
    } else {
      debugPrint(message);
    }
  }
}

extension UpdateOperationsExtension on MixpanelUpdateOperations {
  static const Map<MixpanelUpdateOperations, String> _updateOperations = {
    MixpanelUpdateOperations.$set: '\$set',
    MixpanelUpdateOperations.$setOnce: '\$set_once',
    MixpanelUpdateOperations.$add: '\$add',
    MixpanelUpdateOperations.$append: '\$append',
    MixpanelUpdateOperations.$union: '\$union',
    MixpanelUpdateOperations.$remove: '\$remove',
    MixpanelUpdateOperations.$unset: '\$unset',
    MixpanelUpdateOperations.$delete: '\$delete',
  };

  String get propertyKey => _updateOperations[this]!;
}
