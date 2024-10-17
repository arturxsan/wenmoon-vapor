import NIOSSL
import JWTKit
import Fluent
import FluentPostgresDriver
import APNS
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // Uncomment to serve files from /Public folder if needed
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    if let databaseURL = Environment.get("DATABASE_URL"),
       var postgresConfig = PostgresConfiguration(url: databaseURL) {
        postgresConfig.tlsConfiguration = .makeClientConfiguration()
        postgresConfig.tlsConfiguration?.certificateVerification = .none
        app.databases.use(.postgres(configuration: postgresConfig), as: .psql)
    } else {
        let databaseName: String
        let databasePort: Int

        // Determine database name and port based on environment (testing or production)
        if app.environment == .testing {
            databaseName = "wenmoon_db_test"
            databasePort = 5433
        } else {
            // Use wenmoon_db and localhost for your local setup
            databaseName = Environment.get("DATABASE_NAME") ?? "wenmoon_db"
            databasePort = Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber
        }

        // Use the correct credentials for your local PostgreSQL instance
        app.databases.use(.postgres(
            hostname: Environment.get("DATABASE_HOST") ?? "localhost",
            port: databasePort,
            username: Environment.get("DATABASE_USERNAME") ?? "arturxsan",
            password: Environment.get("DATABASE_PASSWORD") ?? "",
            database: databaseName
        ), as: .psql)
    }
    
    // Add migrations (make sure your migrations are properly configured)
    app.migrations.add([CreatePriceAlert(), CreateCoin()])
    try await app.autoMigrate()

    // Register routes
    try routes(app)
    
    scheduleFetchingCoins(app)

    // Register for sending push notifications (if needed)
    //try configureAPNS(app)

    // Schedule price check for saved alerts (if needed)
    //schedulePriceCheck(app)
}

private func scheduleFetchingCoins(_ app: Application, maxPages: Int = 10, perPage: Int = 250) {
    _ = app.eventLoopGroup.next().scheduleRepeatedAsyncTask(initialDelay: .zero,
                                                            delay: .seconds(180)) { task -> EventLoopFuture<Void> in
        let controller = CoinScannerController()
        let request = Request(application: app, logger: app.logger, on: app.eventLoopGroup.next())

        return fetchMultiplePages(request: request, controller: controller, maxPages: maxPages, perPage: perPage)
    }
}

private func fetchMultiplePages(request: Request, controller: CoinScannerController, maxPages: Int, perPage: Int) -> EventLoopFuture<Void> {
    var futures: [EventLoopFuture<Void>] = []
    
    for page in 1...maxPages {
        let future = controller.fetchCoins(on: request, page: page, perPage: perPage)
        futures.append(future)
    }
    
    return request.eventLoop.flatten(futures).transform(to: ())
}

//private func configureAPNS(_ app: Application) throws {
//    let key: ECDSAKey
//
//    if let keyContent = Environment.get("APNS_KEY") {
//        key = try .private(pem: keyContent)
//    } else {
//        let keyPath = "/Users/artkachenko/Desktop/Developer/My projects/Keys/AuthKey_2Q872WQ32R.p8"
//        key = try .private(filePath: keyPath)
//    }
//
//    let keyID = Environment.get("KEY_ID") ?? "2Q872WQ32R"
//    let teamID = Environment.get("TEAM_ID") ?? "4H24ZTYPFZ"
//    app.apns.configuration = .init(authenticationMethod: .jwt(key: key,
//                                                              keyIdentifier: .init(string: keyID),
//                                                              teamIdentifier: teamID),
//                                   topic: "com.arturxsan.wenmoon",
//                                   environment: .sandbox)
//}
//
//private func schedulePriceCheck(_ app: Application) {
//    _ = app.eventLoopGroup.next().scheduleRepeatedAsyncTask(initialDelay: .seconds(180),
//                                                            delay: .seconds(180)) { task -> EventLoopFuture<Void> in
//        let controller = PriceAlertController()
//        let request = Request(application: app, logger: app.logger, on: app.eventLoopGroup.next())
//        return controller.checkPriceForAlerts(on: request)
//    }
//}
