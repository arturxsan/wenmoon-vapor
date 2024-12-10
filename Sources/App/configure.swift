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
        if app.environment == .testing {
            databaseName = "wenmoon_db_test"
        } else {
            databaseName = Environment.get("DATABASE_NAME") ?? "wenmoon_db"
        }

        app.databases.use(.postgres(
            hostname: Environment.get("DATABASE_HOST") ?? "localhost",
            port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
            username: Environment.get("DATABASE_USERNAME") ?? "arturxsan",
            password: Environment.get("DATABASE_PASSWORD") ?? "",
            database: databaseName,
            maxConnectionsPerEventLoop: 10,
            connectionPoolTimeout: .seconds(60)
        ), as: .psql)
    }
    
    app.migrations.add([CreatePriceAlert(), CreateCoin(), CreateGlobalMarketData()])
    try await app.autoMigrate()

    app.middleware.use(APIKeyMiddleware())
    try routes(app)
    
    if app.environment != .testing {
        CoinScannerController.shared.startFetchingCoinsPeriodically(app: app)
    }

    //try configureAPNS(app)
    //schedulePriceCheck(app)
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
