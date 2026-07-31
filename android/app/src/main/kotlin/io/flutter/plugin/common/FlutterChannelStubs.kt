package io.flutter.plugin.common

/** Minimal compatibility shim retained while native services are disconnected from Flutter. */
class MethodCall(val method: String, private val arguments: Any? = null) {
    @Suppress("UNCHECKED_CAST")
    fun <T> argument(key: String): T? = (arguments as? Map<String, Any?>)?.get(key) as? T
}

class MethodChannel {
    interface Result {
        fun success(result: Any?)
        fun error(errorCode: String, errorMessage: String?, errorDetails: Any?)
        fun notImplemented()
    }
}

class EventChannel {
    interface EventSink {
        fun success(event: Any?)
        fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
        fun endOfStream() {}
    }

    interface StreamHandler {
        fun onListen(arguments: Any?, events: EventSink?)
        fun onCancel(arguments: Any?)
    }
}
