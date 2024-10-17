import XCTVapor
import App

extension Application {
    static func testable() async throws -> Application {
        let app = try await Application.make(.testing)
        try await configure(app)
        return app
    }
}
