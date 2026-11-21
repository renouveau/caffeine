# `Renouveau.Caffeine`

Caffeine is a library for requesting the system not go idle so that long-running tasks continue uninterrupted.  Currently, non-no-op power requests can only be made on Windows.  Support for more operating systems / desktop environments is intended.

**Getting Started.**  Nothing special.  Just install/reference the package in your .NET projects.

**Prerequisites.**  .NET Framework 4.6.1+ or .NET 7.0+.

## usage

```csharp
using Renouveau.Caffeine;

var reason = "Some app is playing music";
var request = PowerRequestFlags.NoIdleDisplay;
using (var prq = PowerRequest.TryCreate(reason, request))
{
  // Code to play music.
}
```

- `PowerRequest` is a disposable type representing a batch of active power requests.  Calling `Dispose` terminates the requests on that object.  If the object becomes unreachable, the finalization mechanism will terminate the requests as a safety net.
- Create `PowerRequest` objects using `PowerRequest.(Try)Create`.  Each overload requires a reason string and can be used for different combinations of required/preferred set of requests.  Consult the XML documentation for platform support and exceptions.
- `PowerRequest` is an abstract type that you cannot meaningfully derive from.
- The type intends to be reliable against thread aborts (.NET Framework) and interruptions.  All public members are thread-safe and safe (as far as exception and CLR integrity are concerned) before/during/after disposal/finalization/resurrection, but they cannot be meaningfully used from finalizers.

## links

- Use this functionality from scripts with [module `RnvPs.Caffeine` in PowerShell Gallery](https://www.powershellgallery.com/packages/RnvPs.Caffeine).
- Visit [GitHub repository `renouveau/caffeine`](https://github.com/renouveau/caffeine) for source code and feedback.
