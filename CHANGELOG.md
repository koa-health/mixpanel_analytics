## [2.1.1] - 2021-06-22

- Fix constructors to use `Stream<String?>?`

## [2.1.0] - 2021-06-22

- Support to add a custom base api url. This basically allows the user to use EU-based web servers as stated in [here](https://developer.mixpanel.com/docs/privacy-security#storing-your-data-in-the-european-union). We're not hardcoding the EU-based url in case Mixpanel considers to add support for more regions.

## [2.0.3] - 2021-06-22

- Fix userId stream type. The `userId` property can be null.

## [2.0.2] - 2021-06-18

- Add support for optionalHeaders and prefsKey

## [2.0.1] - 2021-05-31

- Fix issue with CORS in Flutter web.

## [2.0.0] - 2021-03-09

- Migrate to null safety.

## [1.4.0] - 2021-02-11

- Support for CORS bypass in Flutter web.
- `userId$` is not required anymore. Users can still use that as a way to set up the userId but they can also use the `userId` setter at any time.

## [1.3.1] - 2020-12-20

- Fix a bug that caused the stored in memory events when in batch mode to be overwriten by the first events sent, thus being lost. To avoid a breaking change, the temporal solution was to move the process that pulls from memory old stored not sent events from the batch timer process, to happen when the user sends events for the first time. The problem this solution brings is that we need the caller to push new events in order to get the old stored events to be pushed. If the first thing don't happen the second won't either. But this is better than the previous scenario of lost events. For further details you can check [this PR](https://github.com/koa-health/mixpanel_analytics/pull/9)

## [1.3.0] - 2020-08-19

- Add `useIp` property.

## [1.2.1] - 2019-11-07

- Fix an error when sending batch requests for engage.

## [1.2.0] - 2019-09-10

- Allow encoding function to be passed.

## [1.1.0] - 2019-09-10

- Add option to encode sensitive information to mixpanel.

## [1.0.1] - 2019-08-05

- Add some unit tests.

## [1.0.0] - 2019-08-02

- Initial release.
