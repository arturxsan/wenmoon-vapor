import Fluent
import APNS
import Vapor

struct CoinScannerController {
    func fetchCoins(
        on req: Request,
        currency: String = "usd",
        page: Int = 1,
        perPage: Int = 250
    ) -> EventLoopFuture<Void> {
        guard let url = makeCoinsURL(currency: currency, page: page, perPage: perPage) else {
            return req.eventLoop.makeFailedFuture(Abort(.internalServerError, reason: "Failed to create URL"))
        }
        
        let headers = HTTPHeaders([("User-Agent", "VaporApp/1.0")])
        let urlRequest = ClientRequest(method: .GET, url: URI(string: url.absoluteString), headers: headers)
        
        return req.client.send(urlRequest)
            .flatMap { response in
                guard response.status == .ok, let data = response.body else {
                    let errorMessage = "Failed to fetch coins: \(response.status)"
                    return req.eventLoop.makeFailedFuture(Abort(.internalServerError, reason: errorMessage))
                }
                return self.processCoinsData(data, on: req, page: page)
            }
    }
    
    private func makeCoinsURL(currency: String, page: Int, perPage: Int) -> URL? {
        var urlComponents = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")
        urlComponents?.queryItems = [
            URLQueryItem(name: "vs_currency", value: currency),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        return urlComponents?.url
    }
    
    private func processCoinsData(_ data: ByteBuffer, on req: Request, page: Int) -> EventLoopFuture<Void> {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            let coins = try decoder.decode([Coin].self, from: Data(buffer: data))
            let dbUpserts = coins.map { coin in
                return Coin.query(on: req.db)
                    .filter(\.$coinID == coin.coinID)
                    .first()
                    .flatMap { existingCoin in
                        if let existingCoin = existingCoin {
                            existingCoin.coinName = coin.coinName
                            existingCoin.coinImage = coin.coinImage
                            existingCoin.marketCapRank = coin.marketCapRank
                            existingCoin.currentPrice = coin.currentPrice
                            existingCoin.priceChangePercentage24H = coin.priceChangePercentage24H
                            return existingCoin.update(on: req.db)
                        } else {
                            return coin.create(on: req.db)
                        }
                    }
            }
            print("Fetched page \(page) with coins: \(coins.count)")
            return req.eventLoop.flatten(dbUpserts).transform(to: ())
        } catch {
            return req.eventLoop.makeFailedFuture(error)
        }
    }
}
