import UIKit
import StoreKit

@objc final public class SubscriptionManager: NSObject {
    
    @objc public static let shared = SubscriptionManager()
    var isInitializedWithProductIds = false
    
    @objc var boolShouldShowSuccessAlert:Bool = false
    public typealias ReceiptValidationCompletion     = () -> ()
    
    private var dictionaryProductsForID = [String:InAppProduct]()
    private var boolReceiptLoaded:Bool  = false
    @objc public let notificationHandler = SubManagerNotificationHandler.shared
    
    private let productLoader           = SubProductLoader()
    
    private var lastSubscriptionStatus = false

    @objc public var DEBUG_FOR_ISSUBSCRIBED: Bool = false
    
    
    private override init() {
        super.init()
    }
    
    @objc public func initWithProductIDs(iapSharedSecret: String,
                                         subscriptionProductIDs: [String] = [],
                                         nonConsumableProductIDs: [String] = [],
                                         consumableProductIDs: [String] = []) throws {
        
        if self.isInitializedWithProductIds == false {
            self.attachPaymentObserver(IAP_SHARED_SECRET: iapSharedSecret)
            self.setRequiredNotifications()
            self.productLoader.loadProductIDsInfo(subscriptionProductIDs: subscriptionProductIDs,
                                                  nonConsumableProductIDs: nonConsumableProductIDs,
                                                  consumableProductIDs: consumableProductIDs)
            self.isInitializedWithProductIds = true
        } else {
            print("Subscription Manager Already Initialized!")
        }
        
    }
    
    
    
    @objc public func isNonComsumableTypeProduct(productID: String) -> Bool {
        
        return self.productLoader.getNonConsumableTypeIDs().contains(productID)
        
    }
    
    @objc public func isComsumableTypeProduct(productID: String) -> Bool {
        
        return self.productLoader.getConsumableTypeIDs().contains(productID)
        
    }
    
    @objc public func isSubscriptionTypeProduct(productID: String) -> Bool {
        
        return self.productLoader.getSubscriptionTypeIDs().contains(productID)
        
    }
}

// Handle Notifications
extension SubscriptionManager {
    
    private func setRequiredNotifications() {
        
        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged), name: Notification.Name.reachabilityChanged, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(appWillTerminate), name: UIApplication.willTerminateNotification, object: nil)
        
    }
    
    @objc private func reachabilityChanged(_ notification:Notification) {
        
        IAPLog.event(.reachabilityChanged)
        
        if InternetChecker.shared.isInternetConnected() {
            refreshPurchaseableProducts(nil)
        }
        
        if IAPurchaseHelper.shared.getCurrentSubscriptionStatus() == false {
            actionOnRefreshReceiptCompletion(onServer: true)
        }
    }
    
    @objc private func appWillEnterForeground() {
        
        IAPLog.event(.appWillEnterForeground)
        self.refreshReceiptWhenExpired()
    }
    
    @objc private func appWillTerminate() {
        IAPLog.event(.appWillTerminate)
        self.stopPaymentObserver()
    }
}

//MARK: SKPaymentTransactionObserver
extension SubscriptionManager {
    
    private func attachPaymentObserver(IAP_SHARED_SECRET: String) {
        IAPurchaseHelper.shared.startTransactionObserver(sharedSecrate: IAP_SHARED_SECRET)
    }
    
    private func stopPaymentObserver() {
        IAPurchaseHelper.shared.stopTransactionObserver()
    }
}

//MARK: Request iTune-Server for SkProduct
extension SubscriptionManager {
    
    @objc public func refreshPurchaseableProducts(_ fetchProductCompletion: ((_ skProducts: [InAppProduct]?) -> Void)? = nil) {
        
        guard InternetChecker.shared.isInternetConnected() else {
            if fetchProductCompletion != nil {
                fetchProductCompletion?(nil)
            }
            return
        }
        IAPLog.event(.requestSKProductStarted)
        IAPurchaseHelper.shared.requestProductsFromAppStore(productIDs: productLoader.arrayProductIDInfo, onCompletion: { products in
            
            if let products = products {
                for sub in products {
                    self.dictionaryProductsForID[sub.skProduct.productIdentifier] = sub
                }
            }
            
            if fetchProductCompletion != nil {
                fetchProductCompletion?(products)
            }
            
            self.notificationHandler.notifyObserversForNotificationType(.ProductLoaded, nil)
        })
    }
    
    @objc public func refreshReceiptWhenExpired() {
        
        guard InternetChecker.shared.isInternetConnected() else {
            return
        }
        if IAPurchaseHelper.shared.getCurrentSubscriptionStatus() == false {
            actionOnRefreshReceiptCompletion(onServer: true)
        }
    }
    
    @objc public func actionOnRefreshReceiptCompletion( onServer: Bool, _ completion: ReceiptValidationCompletion? = nil) {
        
        validateReceiptOnline(isOnServer: onServer, on: completion)
    }
    
    private func validateReceiptOnline(isOnServer: Bool, on completion: ReceiptValidationCompletion?) {
        
        print("Validate Receipt Online: \(isOnServer)")
        IAPurchaseHelper.shared.uploadReceiptForValidation(inServer: isOnServer, forceRefresh: false) { receiptValidated in
            
            
            DispatchQueue.main.async(execute: {
                
                self.boolReceiptLoaded = true
                completion?()
                self.notificationHandler.notifyObserversForNotificationType(.PurchaseRecieptLoad, nil)
                
            })
        }
    }
}

//MARK: Request From App Side
extension SubscriptionManager {
    
    @objc public func requestPrice(for productID: String) -> String? {
        
        guard let skProduct = dictionaryProductsForID[productID] else {
            return nil
        }
        return skProduct.currencyFormattedPrice
    }
    
    @objc public func requestPriceInDecimal(for productID: String) -> NSDecimalNumber? {
         
         guard let skProduct = dictionaryProductsForID[productID] else {
             return nil
         }
         return skProduct.productPrice
     }
    
    @objc public func requestIntroductoryPrice(for productID: String) -> String? {
        
        guard let skProduct = dictionaryProductsForID[productID] else {
            return nil
        }
        var priceFormatter = IACommonUtils.currencyFormatter
        
        guard let price = skProduct.skProduct.introductoryPrice?.price else{
            return nil
        }
        if priceFormatter.locale != skProduct.skProduct.priceLocale {
            priceFormatter.locale = skProduct.skProduct.priceLocale
        }
        let currencyFormattedPrice = priceFormatter.string(from: price) ?? "\(price)"

        return currencyFormattedPrice
    }
    
    @objc public func requestIntroductoryPriceInDecimal(for productID: String) -> NSDecimalNumber? {
         
         guard let skProduct = dictionaryProductsForID[productID] else {
             return nil
         }
        return skProduct.skProduct.introductoryPrice?.price
     }
}

//MARK: Request Purchase Actions
extension SubscriptionManager {
    
    @objc public func purchaseRequest(for productID: String, onPurchaseInitiation: ((_ isPurchaseInitiated: Bool)->Void)? = nil) {
        
        if !InternetChecker.shared.isInternetConnected() {
            TopAlertManager.showNoInternetAlert()
            return
        }
        
        ProgressHUD.show("Please wait...", interaction: false)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            ProgressHUD.dismiss()
        }
        
        IAPurchaseHelper.shared.purchaseRequest(for: productID) { isPurchaseInitiated in
            
            if !isPurchaseInitiated {
                
                TopAlertManager.showCustomTopAlert(withBackgroundColor: .blue, withTextColor: .black, withImageName: "Net_Error", withText: "Please try again!") {
                    ProgressHUD.dismiss()
                }
                
            }
            
            if let onCompletion = onPurchaseInitiation {
                onCompletion(isPurchaseInitiated)
            }
        }
    }
}

//MARK: Request Restore Actions
extension SubscriptionManager {
    
    @objc public func restorePurchase(afterProductLoading boolAfterLoading: Bool, andShouldShowSuccessAlert boolShouldShow: Bool) {
        
        if InternetChecker.shared.isInternetConnected() == false {
            TopAlertManager.showNoInternetAlert()
            return
        }
        
        ProgressHUD.show("Please wait...", interaction: false)
        boolShouldShowSuccessAlert = boolShouldShow
        
        if boolAfterLoading {
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
                ProgressHUD.dismiss()
            }
            
            self.refreshPurchaseableProducts({ skProducts in
                IAPurchaseHelper.shared.restorePurchases()
            })
            
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
                ProgressHUD.dismiss()
            }
            
            IAPurchaseHelper.shared.restorePurchases()
            
        }
    }
    
}

extension SubscriptionManager {
    
    @objc public func isSubscribedOrUnlockedAll() -> Bool {
        var isSubscribed = DEBUG_FOR_ISSUBSCRIBED
        
        //MARK: Input All Product ID which need to check for unlock features
        let arrayProductIDsForChecking = self.productLoader.getAllProductIds()

        
        for aProductIdForCheck in arrayProductIDsForChecking {
            isSubscribed = isSubscribed || IAPurchaseHelper.shared.isPurchased(productID: aProductIdForCheck)
        }
        
        // If last SubscriptionStatus true but currently Subscription false that means the previous subscription got expired.
        // A notification for Subscription Expire Sent from here
        
        if lastSubscriptionStatus == true && isSubscribed == false {
            
            lastSubscriptionStatus = isSubscribed
            notificationHandler.notifyObserversForNotificationType(.SubscriptionExpire, nil)
        }
        
        lastSubscriptionStatus = isSubscribed
        return lastSubscriptionStatus
        
    }
    
    @objc public func currentlyPurchasedProductID()-> String?{
        var productIDs : [String] = []
        let arrayProductIDsForChecking = self.productLoader.getAllProductIds()
        
        for aProductIdForCheck in arrayProductIDsForChecking {
            if IAPurchaseHelper.shared.isPurchased(productID: aProductIdForCheck){
                productIDs.append(aProductIdForCheck)
            }
        }
        if productIDs.isEmpty{
            return nil
        }
        return productIDs[0]
    }
    
    @objc public func isIndividuallyPurchased(for productID: String) -> Bool {
        
        return IAPurchaseHelper.shared.isPurchased(productID: productID)
        
    }
}

//MARK: SubProductLoaderProtocol
extension SubscriptionManager: SubProductLoaderProtocol {
    
    @objc public func getProductIDsInfo() -> [ProductIdInfo] {
        return productLoader.getProductIDsInfo()
    }
}

extension SubscriptionManager {
    //TODO: Have to Implement
    //Should return only necessary things not skProduct itself
    @objc public func getProduct(for productId: String) -> SKProduct? {
        
        let skProduct = dictionaryProductsForID[productId]?.skProduct
        return skProduct
        
    }
}

//MARK: Check For Subscription
extension SubscriptionManager {
    
    @objc public func isCurrentSubscription(_ productId: String) -> Bool {
        return productId == IAPurchaseHelper.shared.getCurrentSubscriptionProductID()
    }
    
    @objc public func isTrialPeriodOngoing() -> Bool {
        
        return IAPurchaseHelper.shared.isSubscriptionTrialPeriodOngoing()
    }
  
    @objc public func hasPurchasesHistory() -> Bool {
        
        return IAPurchaseHelper.shared.hasPurchasesHistory()
    }
    @objc public func currentSubscribedProductID() -> String? {
        if IAPurchaseHelper.shared.getCurrentSubscriptionStatus() == false{
            return self.currentlyPurchasedProductID()
        }
        return  IAPurchaseHelper.shared.getCurrentSubscriptionProductID()
    }
    
    @objc public func hasIndividualProductPurchaseHistory(productId : String) -> Bool{
        return IAPurchaseHelper.shared.hasIndividualProductPurchaseHistory(productId: productId)
    }
    
    @objc public func getExpirationDateString() -> String?{
        if IAPurchaseHelper.shared.getCurrentSubscriptionStatus() == false{
            return nil
        }
        return IAPurchaseHelper.shared.getExpirationDateString()
    }
    @objc public func getPurchaseDateString() -> String?{
        if IAPurchaseHelper.shared.getCurrentSubscriptionStatus() == false{
            return nil
        }
        return IAPurchaseHelper.shared.getPurchaseDateString()
    }
    @objc public func isAutoRenewalOn() -> Bool{
        if IAPurchaseHelper.shared.getCurrentSubscriptionStatus() == false{
            return false
        }
        return IAPurchaseHelper.shared.isAutoRenewalOn()

    }
}

//MARK: Free Trial Period
extension SubscriptionManager {
    
    @objc public func getFreeTrialPeriod(for productID: String?, inDays: Bool = true) -> String? {
        
        guard productID != nil else {
            return nil
        }
        
        guard let inAppProduct = IAPurchaseHelper.shared.getInAppProduct(for: productID!) else {
            return nil
        }
        
        let storeKitProduct = inAppProduct.skProduct
        
        guard let introductoryPrice = storeKitProduct.introductoryPrice else {return NO_TRIAL_DAYS}
        
        var freeTrialPeriod: String?
        let numberOfUnits = introductoryPrice.subscriptionPeriod.numberOfUnits
        let periodUnit = introductoryPrice.subscriptionPeriod.unit
        
        if inDays {
            freeTrialPeriod = convertTrialPeriodInDays(for: numberOfUnits, periodUnit: periodUnit)
            
        } else {
            freeTrialPeriod = trialPeriodAsGiven(for: numberOfUnits, periodUnit: periodUnit)
        }
        
        return freeTrialPeriod
    }
    
    public func getFreeTrialPeriodInDaysInteger(for productID: String?) -> Int {
        
        guard productID != nil else {
            return 0
        }
        
        guard let inAppProduct = IAPurchaseHelper.shared.getInAppProduct(for: productID!) else {
            return 0
        }
        
        let storeKitProduct = inAppProduct.skProduct
        
        guard let introductoryPrice = storeKitProduct.introductoryPrice else {return 0}
        
        var freeTrialPeriod: Int
        let numberOfUnits = introductoryPrice.subscriptionPeriod.numberOfUnits
        let periodUnit = introductoryPrice.subscriptionPeriod.unit
        
        freeTrialPeriod = convertTrialPeriodInDaysInteger(for: numberOfUnits, periodUnit: periodUnit)
        
        return freeTrialPeriod
    }
    
    
    private func convertTrialPeriodInDaysInteger(for numberOfUnit: Int, periodUnit: SKProduct.PeriodUnit) -> Int {
        
        var numberOfDays: Int = 0;
        
        switch periodUnit {
            
        case .day:
            numberOfDays = numberOfUnit
        case .week:
            numberOfDays = numberOfUnit * 7
        case .month:
            numberOfDays = numberOfUnit * 30
        case .year:
            numberOfDays = numberOfUnit * 365
        default:
            break
        }
        return numberOfDays
    }
    
    private func convertTrialPeriodInDays(for numberOfUnit: Int, periodUnit: SKProduct.PeriodUnit) -> String {
        
        var numberOfDays: Int = 0;
        
        switch periodUnit {
            
        case .day:
            numberOfDays = numberOfUnit
        case .week:
            numberOfDays = numberOfUnit * 7
        case .month:
            numberOfDays = numberOfUnit * 30
        case .year:
            numberOfDays = numberOfUnit * 365
        default:
            break
        }
        
        var freeTrialPeriod = String(format: "%ld Day", numberOfDays)
        if numberOfDays >= 2 {
            freeTrialPeriod += "s"
        }
        return freeTrialPeriod
    }
    
    private func trialPeriodAsGiven(for numberOfUnit: Int, periodUnit: SKProduct.PeriodUnit) -> String{
        
        var freeTrialPeriod = "";
        
        switch periodUnit {
            
        case .day:
            freeTrialPeriod = String(format: "%ld Day", numberOfUnit)
        case .week:
            freeTrialPeriod = String(format: "%ld Week", numberOfUnit)
        case .month:
            freeTrialPeriod = String(format: "%ld Month", numberOfUnit)
        case .year:
            freeTrialPeriod = String(format: "%ld Year", numberOfUnit)
        default:
            break
        }
        
        if numberOfUnit >= 2 {
            freeTrialPeriod += "s"
        }
        return freeTrialPeriod
    }
    
}

//MARK: ProgressHUD Related
extension SubscriptionManager {
    
    @objc public func progressDismiss() {
        ProgressHUD.dismiss()
    }
}


extension SubscriptionManager{
    @objc public func getRegularProductPeriod(for productID: String) -> String?{
        
        guard let _skProduct = dictionaryProductsForID[productID] else {
            return nil
        }
        let skProduct = _skProduct.skProduct
        
        let val = skProduct.subscriptionPeriod?.numberOfUnits
        return String(describing: val)
    }
    
    
    @objc public func getRegularProductDateType(for productID: String) -> String?{
        
        guard let _skProduct = dictionaryProductsForID[productID] else {
            return nil
        }
        let skProduct = _skProduct.skProduct
        let periodUnit =  skProduct.subscriptionPeriod?.unit
        
        switch periodUnit {
            
        case .day:
            return "day"
        case .week:
            return "week"
        case .month:
            return "month"
        case .year:
            return "year"
        default:
            break
        }
        return nil
    }
    
    @objc public func introductoryProductDuration(for productID: String)-> String?{
        
        guard let _skProduct = dictionaryProductsForID[productID] else {
            return nil
        }
        
        let skProduct = _skProduct.skProduct.introductoryPrice
        guard let skProduct else {
            return nil
        }
        let periodUnit = skProduct.subscriptionPeriod.unit
        let timeForPeriodUnit = skProduct.subscriptionPeriod.numberOfUnits
        
        var dateFormate: String = ""
        switch periodUnit {
            
        case .day:
            dateFormate = String(timeForPeriodUnit) + " day"
        case .week:
            dateFormate = String(timeForPeriodUnit) + " week"
        case .month:
            dateFormate = String(timeForPeriodUnit) + " month"
        case .year:
            dateFormate = String(timeForPeriodUnit) + " year"
        default:
            break
        }
        if timeForPeriodUnit >= 2 {
            dateFormate += "s"
        }
        return dateFormate
    }
    @objc public func numberOfPeriodsRepetition(for productID: String)-> String?{
        guard let skProduct = dictionaryProductsForID[productID] else {
            return nil
        }
        let periods = skProduct.skProduct.introductoryPrice?.numberOfPeriods
        return String(describing: periods)
    }
    @objc public func paymentMode(for productID: String)-> NSDecimalNumber?{
        guard let skProduct = dictionaryProductsForID[productID] else {
            return nil
        }
        let mode = skProduct.skProduct.introductoryPrice?.paymentMode
        switch mode{
        case .freeTrial:
            return 0
        case .payAsYouGo:
            return 1
        case .payUpFront:
            return 2
        default:
            break
        }
        return nil
    }
}

