## [1.3.1] - 2020-12-20

- Fixes a bug that involved the stored in memory events when in batch mode to be lost. To avoid a breaking change, a temporal solution is to move the process that pulls from memory old stored not sent events from the batch timer process to happen when the user sends events for the first time. The problem this solution brings is that we need the caller to push new events in order to get the old stored events to be pushed. If the first thing don't happen the second won't either. But this is better than the previous scenario of lost events. For further details you can check [this PR](https://github.com/koa-health/mixpanel_analytics/pull/9)

## [1.3.0] - 2020-08-19

- Added `useIp` property.

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
