import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mixpanel_analytics/mixpanel_analytics.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _user$ = StreamController<String>.broadcast();

  MixpanelAnalytics _mixpanel;
  MixpanelAnalytics _mixpanelBatch;

  String _error;
  String _success;

  int _levelNumber = 0;

  @override
  void initState() {
    super.initState();

    _mixpanel = MixpanelAnalytics(
      token: 'XXXX',
      userId$: _user$.stream,
      verbose: true,
      shouldAnonymize: true,
      shaFn: (value) => value,
      onError: (e) => setState(() {
        _error = e;
        _success = null;
      }),
    );

    _mixpanelBatch = MixpanelAnalytics.batch(
      token: 'XXXX',
      userId$: _user$.stream,
      uploadInterval: Duration(seconds: 30),
      shouldAnonymize: true,
      shaFn: (value) => value,
      verbose: true,
      onError: (e) => setState(() {
        _error = e;
        _success = null;
      }),
    );

    _user$.add('111112');
  }

  @override
  void dispose() {
    _user$.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RaisedButton(
              child: Text('Send track event'),
              onPressed: () async {
                var result = await _mixpanel
                    .track(event: 'testEvent', properties: {'prop1': 'value1'});
                if (result) {
                  setState(() {
                    _success = 'Success!';
                    _error = '';
                  });
                }
              },
            ),
            RaisedButton(
              child: Text('Send engage event'),
              onPressed: () async {
                var result = await _mixpanel
                    .engage(operation: MixpanelUpdateOperations.$set, value: {
                  'Level Number': _levelNumber,
                });
                _levelNumber++;
                if (result) {
                  setState(() {
                    _success = 'Success!';
                    _error = '';
                  });
                }
              },
            ),
            RaisedButton(
              child: Text('Send track event in batch'),
              onPressed: () async {
                var result = await _mixpanelBatch
                    .track(event: 'testEvent', properties: {'prop1': 'value1'});
                if (result) {
                  setState(() {
                    _success = 'Success!';
                    _error = '';
                  });
                }
              },
            ),
            RaisedButton(
              child: Text('Send engage event in batch'),
              onPressed: () async {
                var result = await _mixpanelBatch
                    .engage(operation: MixpanelUpdateOperations.$set, value: {
                  'Level Number': _levelNumber,
                });
                _levelNumber++;
                if (result) {
                  setState(() {
                    _success = 'Success!';
                    _error = '';
                  });
                }
              },
            ),
            _error != null ? Text(_error) : Container(),
            _success != null ? Text(_success) : Container(),
          ],
        ),
      ),
    );
  }
}
