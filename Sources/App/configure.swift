import NIOSSL
import JWTKit
import Fluent
import FluentPostgresDriver
import APNS
import Vapor

public func configure(_ app: Application) async throws {
    if let databaseURL = Environment.get("DATABASE_URL"),
       var postgresConfig = PostgresConfiguration(url: databaseURL) {
        postgresConfig.tlsConfiguration = .makeClientConfiguration()
        postgresConfig.tlsConfiguration?.certificateVerification = .none
        app.databases.use(.postgres(configuration: postgresConfig), as: .psql)
    } else {
        let databaseName: String
        let databasePort: Int

        if app.environment == .testing {
            databaseName = "wenmoon_db_test"
            databasePort = 5433
        } else {
            databaseName = Environment.get("DATABASE_NAME") ?? "wenmoon_db"
            databasePort = Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber
        }

        app.databases.use(.postgres(
            hostname: Environment.get("DATABASE_HOST") ?? "localhost",
            port: databasePort,
            username: Environment.get("DATABASE_USERNAME") ?? "arturxsan",
            password: Environment.get("DATABASE_PASSWORD") ?? "",
            database: databaseName
        ), as: .psql)
    }
    
    app.migrations.add([CreatePriceAlert(), CreateCoin()])
    try await app.autoMigrate()

    try routes(app)
    
    if app.environment != .testing {
        scheduleFetchingCoins(app)
    }

    //try configureAPNS(app)
    //schedulePriceCheck(app)
}

private func scheduleFetchingCoins(_ app: Application, maxPages: Int = 10, perPage: Int = 250) {
    _ = app.eventLoopGroup.next().scheduleRepeatedAsyncTask(
        initialDelay: .zero,
        delay: .seconds(60)
    ) { task -> EventLoopFuture<Void> in
        let controller = CoinScannerController()
        let request = Request(application: app, logger: app.logger, on: app.eventLoopGroup.next())
        return fetchMultiplePages(request: request, controller: controller, maxPages: maxPages, perPage: perPage)
    }
}

private func fetchMultiplePages(request: Request, controller: CoinScannerController, maxPages: Int, perPage: Int) -> EventLoopFuture<Void> {
    var future: EventLoopFuture<Void> = request.eventLoop.makeSucceededFuture(())
    
    for page in 1...maxPages {
        future = future.flatMap {
            // Fetch the coins for the current page
            controller.fetchCoins(on: request, page: page, perPage: perPage)
        }
        .flatMap {
            // Wait for 60 seconds after fetching the current page (except the last one)
            if page < maxPages {
                return request.eventLoop.scheduleTask(in: .seconds(60)) {}.futureResult
            }
            return request.eventLoop.makeSucceededFuture(())
        }
    }
    return future.flatMap {
        print("All \(maxPages) pages have been fetched.")
        return request.eventLoop.makeSucceededFuture(())
    }
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
