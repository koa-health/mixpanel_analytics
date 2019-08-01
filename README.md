# Mixpanel Analytics

[![Build Status](https://travis-ci.com/Alpha-health/mixpanel_analytics.svg?token=86N6VqHRALbz6yZmArqS&branch=master)](https://travis-ci.com/Alpha-health/mixpanel_analytics) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A dart wrapper on the mixpanel REST API to be used in Flutter applications.
As this is using the http REST API it works both with Android and iOS.

## How to use it

There is an [example](./example) app that demonstrates how to use the plugin,

You just need to instantiate the class and you'll be ready to send `track` or `engage` events.

Make sure to check [mixpanel documentation](https://developer.mixpanel.com/docs/http) for the REST API to know the options available.

```dart
MixpanelAnalytics(
  token: 'XXXXXXXXX',
  userId$: _user$.stream,
  verbose: true,
  onError: (e) => setState(() {
    _error = e;
    _success = null;
  }),
);
```

There are two different constructors, the regular one which will send events on the fly and the `batch` mode which will group the requests (by type) and send them every X seconds (configurable).

```dart
MixpanelAnalytics.batch(
  token: 'XXXXXXXXX',
  userId$: _user$.stream,
  uploadInterval: Duration(seconds: 30),
  verbose: true,
  onError: (e) => setState(() {
    _error = e;
    _success = null;
  }),
);
```

## Not supported yet

Check the documentation for more information on the features not yet supported [https://developer.mixpanel.com/docs/http](https://developer.mixpanel.com/docs/http)

### Event Request Parameters

In addition to the `data` parameter, `https://api.mixpanel.com/track` supports a number of optional parameters. For the most part, these optional parameters are useful only in special situations.

| Parameters |
| :--------- |
| ip         |
| redirect   |
| img        |
| callback   |

### Update Request Parameters

In addition to the `data` parameter, `https://api.mixpanel.com/engage` supports a number of optional parameters. For the most part, these optional parameters are useful only in special situations.

| Parameters |
| :--------- |
| redirect   |
| callback   |

### Invalid requests

When sending batch requests, if one of them is invalid the whole batch operation will fail and the batch will be saved to retry the next iteration.
This could become a problem as the whole batch could be stored and retried over and over.
A strategy for this would be either to send individually the requests and ditch the only invalid one or just dith the whole lot (TBD).
