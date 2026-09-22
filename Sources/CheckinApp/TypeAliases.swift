import CheckinCore

/// Typealias mapping the value type `Task` to `CheckinCore.Task`.
///
/// Swift's standard library also has a concurrency type named `Task`, which collides with this
/// project's value type. Declaring the typealias at module scope makes every `Task` reference in
/// CheckinApp resolve to `CheckinCore.Task` (not the standard library's concurrency Task).
typealias Task = CheckinCore.Task
