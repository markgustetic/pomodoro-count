# Stop confirmation

Confirm before the panel throws away a session or a break.

## Scope

Four presses ask "are you sure?" through a popover anchored to the button
that was pressed:

| Control | Phase        | Title                 | Note                                           | Verb        |
|---------|--------------|-----------------------|------------------------------------------------|-------------|
| Stop    | `.breakReady`| Skip the break?       | The session is already logged.                 | Skip        |
| Stop    | `.work`      | Abandon this session? | Nothing is logged.                             | Abandon     |
| Stop    | `.breakTime` | Cut the break short?  | Back to idle; the session stays logged.        | Stop        |
| Cup     | `.work`      | Rest now?             | The unfinished session isn't logged.           | Start break |

The cup while idle acts immediately: nothing is lost there. The stop button is
disabled while idle already. No Settings switch.

## Why a popover

Alerts and `confirmationDialog` close the non-activating panel they would be
confirming in (see the agent guide). `RemoveCategoryConfirmation` is the
precedent: a popover that paints its own themed background, cancels on Esc,
and gives Return nothing to do so the destructive verb takes a click.

## Shape

- `StopConfirmation.prompt(phase:)` and `StopConfirmation.restNowPrompt` are
  pure and unit-tested; the switch is exhaustive so a new `Phase` fails to
  compile rather than showing the wrong words.
- `StopConfirmationView` takes closures, not the model (`@EnvironmentObject`
  crashes in popover content).
- `RootView`'s focus tab holds one `@State` flag per button. `AppModel` is
  untouched: hotkeys and the URL scheme never called `reset()` and still don't.
