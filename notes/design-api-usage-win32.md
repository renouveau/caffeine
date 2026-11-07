# API usage in `PlatformPowerRequests.Win32`

Currently, Win32 implementation of `PowerRequest` uses [`SetThreadExecutionState`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate) instead of the newer [`PowerCreateRequest` series](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-powercreaterequest).  The reason is *not* that `SetThreadExecutionState` is supported on earlier systems than `PowerCreateRequest`.

Per the documentation of [`PowerSetRequest`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-powersetrequest#remarks), using it to request system (do not idle to sleep) or execution (only applicable to suspension of Windows Store apps) will become ineffective 5 minutes after system sleep timer expires on Connected Standby on battery.  It also mentions that away-mode requests are terminated once the user initiates a sleep on non-S3 machines.  In contrast, the documentation of [`SetThreadExecutionState`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate) doesn’t mention such restrictions.  This is the reason that moved the needle, despite `PowerCreateRequest` is more user-friendly as it allows us to set a description.

~~It’s well possible that `SetThreadExecutionState` is subject to the same set of constraints, just not stated.  Here, I utilize prayer-based programming.~~  Tested on Windows 11 version 25H2 (x64) on ThinkPad X9 15 Aura Edition (a device with Connected Standby):

- the device is on battery power and has Connected Standby enabled;
- the system has a 3-minute display/sleep timer;
- when `SetThreadExecutionState` sets the thread for continuous display (monitor) usage (for 11 minutes), the display does not dim for the duration of the request;
- once `SetThreadExecutionState` reverts the request, the display/sleep timer restarts, the display dims when 3 minutes are about to pass, and it is turned off after 3 minutes.

Moreover, away mode requested by `SetThreadExecutionState` is still in effect when the system wakes up from sleep after being put to sleep by me (choosing Sleep in “Start”; all on battery), as reported by `powercfg /requests`, so it is not subject to termination after user-initiated sleep, which `PowerSetRequest` is documented to be subject to.

~~The tests show `SetThreadExecutionState` achieves the goal.  I have no plan to switch the calls to `PowerCreateRequest` series, until I get time to test its behavior.~~ Further tests showed the following behavior on Connected Standby on battery (idle time-out is 3 minutes):

- if only `ES_CONTINUOUS | ES_DISPLAY_REQUIRED` are set, the display is not turned off for the duration of the state and it is turned off 3 minutes after the state is cleared;
- if only `ES_CONTINUOUS | ES_SYSTEM_REQUIRED` are set, the display turns off after 3 minutes and execution continues for another 5 minutes, then execution suspends;
- if only `ES_CONTINUOUS | ES_AWAY_MODE_REQUIRED` are set, the display turns off and execution suspends after 3 minutes.

In the latter cases, after waking up, the request is still shown in `powercfg /requests`.  Therefore, the execution states set by `SetThreadExecutionState` have the ignoring semantics of `PowerSetRequest`, but they’re not *terminated*.

The documentation of `PowerSetRequest` says system request must be taken, when display request is taken, to keep the screen on.  In `SetThreadExecutionState`, a display request by itself keeps the screen on.  Further testing of `PowerSetRequest` is needed (to see if the documentation is in fact inaccurate) before I switch to it.
