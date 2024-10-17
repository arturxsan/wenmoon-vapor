@testable import App
import Fluent
import XCTVapor

final class PriceAlertTests: XCTestCase {
    // MARK: - Properties
    var app: Application!
    var headers: HTTPHeaders!
    
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
    // Get Price Alerts
    func testGetPriceAlertsSuccess() async throws {
        let bitcoinPriceAlert = try await createBitcoinPriceAlert()
        let ethereumPriceAlert = try await createEthereumPriceAlert()
        try app.test(.GET, "price-alerts") { response in
            XCTAssertEqual(response.status, .ok)
            let priceAlerts = try response.content.decode([PriceAlert].self)
            XCTAssertEqual(priceAlerts.count, 2)
            assertPriceAlert(priceAlerts.first!, bitcoinPriceAlert)
            assertPriceAlert(priceAlerts.last!, ethereumPriceAlert)
        }
    }
    
    func testGetPriceAlertsEmptyArray() throws {
        try app.test(.GET, "price-alerts") { response in
            XCTAssertEqual(response.status, .ok)
            let priceAlerts = try response.content.decode([PriceAlert].self)
            XCTAssertTrue(priceAlerts.isEmpty)
        }
    }
    
    func testGetSpecificPriceAlerts() async throws {
        let bitcoinPriceAlert = try await createBitcoinPriceAlert()
        // Test for existing price alert
        try app.test(.GET, "price-alerts", headers: headers) { response in
            XCTAssertEqual(response.status, .ok)
            let priceAlerts = try response.content.decode([PriceAlert].self)
            XCTAssertEqual(priceAlerts.count, 1)
            assertPriceAlert(priceAlerts.first!, bitcoinPriceAlert)
        }
        // Test for non-existing price alert
        headers = HTTPHeaders([("X-Device-ID", "non-existing-device-token")])
        try app.test(.GET, "price-alerts", headers: headers) { response in
            XCTAssertEqual(response.status, .ok)
            let priceAlerts = try response.content.decode([PriceAlert].self)
            XCTAssertTrue(priceAlerts.isEmpty)
        }
    }
    
    // Post Price Alert
    func testPostPriceAlertSuccess() async throws {
        let bitcoinPriceAlert = makeBitcoinPriceAlert()
        let postedPriceAlert = try postPriceAlert(bitcoinPriceAlert)
        try app.test(.GET, "price-alerts", afterResponse: { response in
            let priceAlerts = try response.content.decode([PriceAlert].self)
            XCTAssertEqual(priceAlerts.count, 1)
            assertPriceAlert(postedPriceAlert!, priceAlerts.first!)
        })
    }
    
    func testPostDuplicatePriceAlert() async throws {
        let bitcoinPriceAlert = makeBitcoinPriceAlert()
        _ = try postPriceAlert(bitcoinPriceAlert)
        try app.test(.POST, "price-alert", headers: headers, beforeRequest: { req in
            try req.content.encode(bitcoinPriceAlert)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .conflict)
            XCTAssertTrue(response.body.string.contains("Price alert already exists for this coin and device."))
        })
    }
    
    func testPostEmptyPriceAlert() throws {
        try app.test(.POST, "price-alert", beforeRequest: { req in
            let emptyPriceAlert = makeEmptyPriceAlert()
            try req.content.encode(emptyPriceAlert)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .badRequest)
            XCTAssertTrue(response.body.string.contains("coin_id parameter must not be empty"))
        })
    }
    
    func testPostInvalidPriceAlert() async throws {
        let invalidPriceAlert = makeInvalidPriceAlert()
        try app.test(.POST, "price-alert", beforeRequest: { req in
            try req.content.encode(invalidPriceAlert)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .badRequest)
            XCTAssertTrue(response.body.string.contains("target_price must be greater than zero"))
        })
    }
    
    // Delete Price Alert
    func testDeletePriceAlert() async throws {
        let bitcoinPriceAlert = try await createBitcoinPriceAlert()
        // Successful deletion
        try app.test(.DELETE, "price-alert/\(bitcoinPriceAlert.coinID)", headers: headers) { response in
            XCTAssertEqual(response.status, .ok)
            let deletedPriceAlert = try response.content.decode(PriceAlert.self)
            assertPriceAlert(bitcoinPriceAlert, deletedPriceAlert)
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
        try app.test(.DELETE, "price-alert/\(bitcoinPriceAlert.coinID)") { response in
            XCTAssertEqual(response.status, .badRequest)
            XCTAssertTrue(response.body.string.contains("X-Device-ID header missing"))
        }
    }
    
    // MARK: - Helpers
    private func makePriceAlert(
        coinID: String = "",
        coinName: String = "",
        targetPrice: Double = .zero,
        targetDirection: PriceAlert.TargetDirection = .below,
        deviceToken: String = ""
    ) -> PriceAlert {
        PriceAlert(
            coinID: coinID,
            coinName: coinName,
            targetPrice: targetPrice,
            targetDirection: targetDirection,
            deviceToken: deviceToken
        )
    }
    
    private func makePredefinedPriceAlert(
        coinID: String,
        coinName: String,
        targetPrice: Double,
        targetDirection: PriceAlert.TargetDirection,
        deviceToken: String
    ) -> PriceAlert {
        makePriceAlert(
            coinID: coinID,
            coinName: coinName,
            targetPrice: targetPrice,
            targetDirection: targetDirection,
            deviceToken: deviceToken
        )
    }
    
    private func makeBitcoinPriceAlert() -> PriceAlert {
        makePredefinedPriceAlert(
            coinID: "bitcoin",
            coinName: "Bitcoin",
            targetPrice: 70000,
            targetDirection: .above,
            deviceToken: "98a6de3ab414ef58b9aa38e8cf1570a4d329e3235ec8c0f343fe75ae51870030"
        )
    }
    
    private func makeInvalidPriceAlert() -> PriceAlert {
        makePredefinedPriceAlert(
            coinID: "bitcoin",
            coinName: "Bitcoin",
            targetPrice: -1,
            targetDirection: .above,
            deviceToken: "98a6de3ab414ef58b9aa38e8cf1570a4d329e3235ec8c0f343fe75ae51870030"
        )
    }
    
    private func makeEmptyPriceAlert() -> PriceAlert {
        makePriceAlert()
    }
    
    private func createPriceAlert(
        coinID: String,
        coinName: String,
        targetPrice: Double,
        targetDirection: PriceAlert.TargetDirection,
        deviceToken: String
    ) async throws -> PriceAlert {
        let priceAlert = makePriceAlert(
            coinID: coinID,
            coinName: coinName,
            targetPrice: targetPrice,
            targetDirection: targetDirection,
            deviceToken: deviceToken
        )
        try await priceAlert.save(on: app.db)
        return priceAlert
    }
    
    private func createBitcoinPriceAlert() async throws -> PriceAlert {
        try await createPriceAlert(
            coinID: "bitcoin",
            coinName: "Bitcoin",
            targetPrice: 70000,
            targetDirection: .above,
            deviceToken: "98a6de3ab414ef58b9aa38e8cf1570a4d329e3235ec8c0f343fe75ae51870030"
        )
    }
    
    private func createEthereumPriceAlert() async throws -> PriceAlert {
        try await createPriceAlert(
            coinID: "ethereum",
            coinName: "Ethereum",
            targetPrice: 2000,
            targetDirection: .below,
            deviceToken: "98a6de3ab414ef58b9aa38e8cf1570a4d329e3235ec8c0f343fe75ae51870031"
        )
    }
    
    private func assertPriceAlert(_ expected: PriceAlert, _ actual: PriceAlert) {
        XCTAssertEqual(expected.coinID, actual.coinID)
        XCTAssertEqual(expected.coinName, actual.coinName)
        XCTAssertEqual(expected.targetPrice, actual.targetPrice)
        XCTAssertEqual(expected.targetDirection, actual.targetDirection)
        XCTAssertEqual(expected.deviceToken, actual.deviceToken)
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
}
