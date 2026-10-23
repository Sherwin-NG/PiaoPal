import os.log

enum Log {
    static let engine  = Logger(subsystem: "io.github.sherwinng.PiaoPal", category: "engine")
    static let render  = Logger(subsystem: "io.github.sherwinng.PiaoPal", category: "render")
    static let input   = Logger(subsystem: "io.github.sherwinng.PiaoPal", category: "input")
    static let skin    = Logger(subsystem: "io.github.sherwinng.PiaoPal", category: "skin")
    static let store   = Logger(subsystem: "io.github.sherwinng.PiaoPal", category: "store")
}
