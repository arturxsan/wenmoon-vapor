@testable import App
import Fluent
import XCTVapor

final class PriceAlertTests: XCTestCase {
    // MARK: - Properties
    var app: Application!
    private var headers: HTTPHeaders!

    // MARK: - Setup
    override func setUp() async throws {
        app = try await Application.testable()
        headers = HTTPHeaders([("X-Device-ID", "98a6de3ab414ef58b9aa38e8cf1570a4d329e3235ec8c0f343fe75ae51870030")])
    }
    
    override func tearDown() async throws {
        try await app.autoRevert()
        try await app.asyncShutdown()
    }
    
    // MARK: - Tests
    func testGetAllPriceAlerts() async throws {
        let priceAlert1 = try await create(makePriceAlert(), on: app.db)
        let priceAlert2 = try await create(makePriceAlert(coinID: "ethereum"), on: app.db)

        try app.test(.GET, "price-alerts") { response in
            XCTAssertEqual(response.status, .ok)
            let priceAlerts = try response.content.decode([PriceAlert].self)
            XCTAssertEqual(priceAlerts.count, 2)
            XCTAssertEqual(priceAlerts.map { $0.coinID }, [priceAlert1.coinID, priceAlert2.coinID])
        }
    }

    func testGetAllPriceAlertsEmptyArray() throws {
        try app.test(.GET, "price-alerts") { response in
            XCTAssertEqual(response.status, .ok)
            let priceAlerts = try response.content.decode([PriceAlert].self)
            XCTAssertTrue(priceAlerts.isEmpty)
        }
    }

    func testGetSpecificPriceAlerts() async throws {
        let priceAlert = try await create(makePriceAlert(), on: app.db)
        
        // Test for existing price alert
        try app.test(.GET, "price-alerts", headers: headers) { response in
            XCTAssertEqual(response.status, .ok)
            let priceAlerts = try response.content.decode([PriceAlert].self)
            XCTAssertEqual(priceAlerts.count, 1)
            assertPriceAlert(priceAlert, priceAlerts.first!)
        }
        
        // Test for non-existing price alert
        headers = HTTPHeaders([("X-Device-ID", "non-existing-device-token")])
        try app.test(.GET, "price-alerts", headers: headers) { response in
            XCTAssertEqual(response.status, .ok)
            let priceAlerts = try response.content.decode([PriceAlert].self)
            XCTAssertTrue(priceAlerts.isEmpty)
        }
    }

    func testPostPriceAlertSuccess() async throws {
        let postedPriceAlert = try postPriceAlert(makePriceAlert())
        try app.test(.GET, "price-alerts", afterResponse: { response in
            let priceAlerts = try response.content.decode([PriceAlert].self)
            XCTAssertEqual(priceAlerts.count, 1)
            assertPriceAlert(postedPriceAlert!, priceAlerts.first!)
        })
    }

    func testPostPriceAlertFailure() throws {
        try app.test(.POST, "price-alert", beforeRequest: { req in
            try req.content.encode(makePriceAlert(coinID: ""))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .badRequest)
            XCTAssertTrue(response.body.string.contains("coin_id parameter must not be empty"))
        })
    }

    func testDeletePriceAlert() async throws {
        let priceAlert = try await create(makePriceAlert(), on: app.db)
        
        // Successful deletion
        try app.test(.DELETE, "price-alert/\(priceAlert.coinID)", headers: headers) { response in
            XCTAssertEqual(response.status, .ok)
            let deletedPriceAlert = try response.content.decode(PriceAlert.self)
            assertPriceAlert(priceAlert, deletedPriceAlert)

            // Confirm deletion
            try app.test(.GET, "price-alerts") { secondResponse in
                XCTAssertEqual(secondResponse.status, .ok)
                let priceAlerts = try secondResponse.content.decode([PriceAlert].self)
                XCTAssertEqual(priceAlerts.count, .zero)
            }
        }
        
        // Invalid ID deletion
        let invalidCoinID = "invalid-coin-id"
        try app.test(.DELETE, "price-alert/\(invalidCoinID)", headers: headers) { response in
            XCTAssertEqual(response.status, .notFound)
            XCTAssertTrue(response.body.string.contains("Could not find price alert with the following coin id: \(invalidCoinID)"))
        }

        // Missing header
        try app.test(.DELETE, "price-alert/\(priceAlert.coinID)") { response in
            XCTAssertEqual(response.status, .badRequest)
            XCTAssertTrue(response.body.string.contains("X-Device-ID header missing"))
        }
    }

    func testPostDuplicatePriceAlert() async throws {
        let priceAlert = makePriceAlert()
        _ = try postPriceAlert(priceAlert)

        // Attempt to post the same price alert again
        try app.test(.POST, "price-alert", headers: headers, beforeRequest: { req in
            try req.content.encode(priceAlert)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .conflict)
        })
    }

    func testPostInvalidPriceAlertParameters() throws {
        let invalidPriceAlert = makePriceAlert(targetPrice: -1)

        try app.test(.POST, "price-alert", beforeRequest: { req in
            try req.content.encode(invalidPriceAlert)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .badRequest)
            XCTAssertTrue(response.body.string.contains("target_price must be greater than zero"))
        })
    }

    func testResponseStructure() async throws {
        _ = try await create(makePriceAlert(), on: app.db)

        try app.test(.GET, "price-alerts") { response in
            XCTAssertEqual(response.status, .ok)
            let priceAlerts = try response.content.decode([PriceAlert].self)

            XCTAssertEqual(priceAlerts.count, 1)
            let returnedAlert = priceAlerts.first!

            XCTAssertNotNil(returnedAlert.coinID)
            XCTAssertNotNil(returnedAlert.coinName)
            XCTAssertNotNil(returnedAlert.targetPrice)
            XCTAssertNotNil(returnedAlert.targetDirection)
            XCTAssertNotNil(returnedAlert.deviceToken)
        }
    }

    // MARK: - Helpers
    private func makePriceAlert(
        coinID: String = "bitcoin",
        coinName: String = "Bitcoin",
        targetPrice: Double = 30000,
        targetDirection: PriceAlert.TargetDirection = .above,
        deviceToken: String = "98a6de3ab414ef58b9aa38e8cf1570a4d329e3235ec8c0f343fe75ae51870030"
    ) -> PriceAlert {
        return PriceAlert(
            coinID: coinID,
            coinName: coinName,
            targetPrice: targetPrice,
            targetDirection: targetDirection,
            deviceToken: deviceToken
        )
    }
    
    private func create(_ priceAlert: PriceAlert, on database: Database) async throws -> PriceAlert {
        try await priceAlert.save(on: database)
        return priceAlert
    }
    
    private func postPriceAlert(_ priceAlert: PriceAlert, expectedStatus: HTTPResponseStatus = .ok) throws -> PriceAlert? {
        var receivedPriceAlert: PriceAlert?
        try app.test(.POST, "price-alert", headers: headers, beforeRequest: { req in
            try req.content.encode(priceAlert)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, expectedStatus)
            receivedPriceAlert = try response.content.decode(PriceAlert.self)
        })
        return receivedPriceAlert
    }
    
    private func assertPriceAlert(_ expected: PriceAlert, _ actual: PriceAlert) {
        XCTAssertEqual(expected.coinID, actual.coinID)
        XCTAssertEqual(expected.coinName, actual.coinName)
        XCTAssertEqual(expected.targetPrice, actual.targetPrice)
        XCTAssertEqual(expected.targetDirection, actual.targetDirection)
        XCTAssertEqual(expected.deviceToken, actual.deviceToken)
    }
}
