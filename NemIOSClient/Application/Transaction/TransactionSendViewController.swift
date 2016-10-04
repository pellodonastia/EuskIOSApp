//
//  TransactionSendViewController.swift
//
//  This file is covered by the LICENSE file in the root of this project.
//  Copyright (c) 2016 NEM
//

import UIKit
import SwiftyJSON

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}

/**
    The view controller that lets the user send transactions from
    the current account or the accounts the current account is a 
    cosignatory of.
 */
class TransactionSendViewController: UIViewController, UIScrollViewDelegate {
    
    // MARK: - View Controller Properties
    
    var recipientAddress: String?
    var amount: Double?
    var message: String?
    fileprivate var account: Account?
    fileprivate var accountData: AccountData?
    fileprivate var activeAccountData: AccountData?
    fileprivate var willEncrypt = false
    fileprivate var accountChooserViewController: UIViewController?
    fileprivate var preparedTransaction: Transaction?
    
    // MARK: - View Controller Outlets
    
    @IBOutlet weak var customScrollView: UIScrollView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var transactionAccountChooserButton: AccountChooserButton!
    @IBOutlet weak var transactionSenderHeadingLabel: UILabel!
    @IBOutlet weak var transactionSenderLabel: UILabel!
    @IBOutlet weak var transactionRecipientHeadingLabel: UILabel!
    @IBOutlet weak var transactionRecipientTextField: NEMTextField!
    @IBOutlet weak var transactionAmountHeadingLabel: UILabel!
    @IBOutlet weak var transactionAmountTextField: UITextField!
    @IBOutlet weak var transactionMessageHeadingLabel: UILabel!
    @IBOutlet weak var transactionMessageTextField: UITextField!
    @IBOutlet weak var transactionEncryptionButton: UIButton!
    @IBOutlet weak var transactionFeeHeadingLabel: UILabel!
    @IBOutlet weak var transactionFeeTextField: UITextField!
    @IBOutlet weak var transactionSendButton: UIButton!
    @IBOutlet weak var navigationBar: UINavigationBar!
    @IBOutlet weak var customNavigationItem: UINavigationItem!
    @IBOutlet weak var viewTopConstraint: NSLayoutConstraint!
    
    // MARK: - View Controller Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationBar.delegate = self
        
        account = AccountManager.sharedInstance.activeAccount
        
        guard account != nil else {
            print("Critical: Account not available!")
            return
        }
        
        updateViewControllerAppearance()
        fetchAccountData(forAccount: account!)
        
        if recipientAddress != nil {
            transactionRecipientTextField.text = recipientAddress
        }
        if amount != nil {
            transactionAmountTextField.text = "\(amount!)"
        }
        if message != nil {
            transactionMessageTextField.text = message
        }
        
        calculateTransactionFee()
        
//        setSuggestions()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        viewTopConstraint.constant = self.navigationBar.frame.height
    }
    
    // MARK: - View Controller Helper Methods
    
    /// Updates the appearance (coloring, titles) of the view controller.
    fileprivate func updateViewControllerAppearance() {
        
        customNavigationItem.title = "NEW_TRANSACTION".localized()
        transactionSenderHeadingLabel.text = "FROM".localized() + ":"
        transactionRecipientHeadingLabel.text = "TO".localized() + ":"
        transactionAmountHeadingLabel.text = "AMOUNT".localized() + ":"
        transactionMessageHeadingLabel.text = "MESSAGE".localized() + ":"
        transactionFeeHeadingLabel.text = "FEE".localized() + ":"
        transactionSendButton.setTitle("SEND".localized(), for: UIControlState())
        transactionRecipientTextField.placeholder = "ENTER_ADDRESS".localized()
        transactionAmountTextField.placeholder = "ENTER_AMOUNT".localized()
        transactionMessageTextField.placeholder = "EMPTY_MESSAGE".localized()
        transactionFeeTextField.placeholder = "ENTER_FEE".localized()
    }
    
    /**
        Shows an alert view controller with the provided alert message.
     
        - Parameter message: The message that should get shown.
        - Parameter completion: An optional action that should get performed on completion.
     */
    fileprivate func showAlert(withMessage message: String, completion: ((Void) -> Void)? = nil) {
        
        let alert = UIAlertController(title: "INFO".localized(), message: message, preferredStyle: UIAlertControllerStyle.alert)
        
        alert.addAction(UIAlertAction(title: "OK".localized(), style: UIAlertActionStyle.default, handler: { (action) -> Void in
            alert.dismiss(animated: true, completion: nil)
            completion?()
        }))
        
        present(alert, animated: true, completion: nil)
    }
    
    /**
        Updates the form with the fetched account details.
     
        - Parameter accountData: The account data with which the form should get updated.
     */
    fileprivate func updateForm(withAccountData accountData: AccountData) {
        
        if accountData.cosignatoryOf.count > 0 {
            transactionAccountChooserButton.isHidden = false
            transactionSenderLabel.isHidden = true
            transactionAccountChooserButton.setTitle(accountData.title ?? accountData.address, for: UIControlState())
        } else {
            transactionAccountChooserButton.isHidden = true
            transactionSenderLabel.isHidden = false
            transactionSenderLabel.text = accountData.title ?? accountData.address
        }

        let amountAttributedString = NSMutableAttributedString(string: "\("AMOUNT".localized()) (\("BALANCE".localized()): ", attributes: [NSFontAttributeName: UIFont.systemFont(ofSize: 17)])
        amountAttributedString.append(NSMutableAttributedString(string: "\((accountData.balance / 1000000).format())", attributes: [NSForegroundColorAttributeName: UIColor(red: 51.0/255.0, green: 191.0/255.0, blue: 86.0/255.0, alpha: 1.0), NSFontAttributeName: UIFont.systemFont(ofSize: 17)]))
        amountAttributedString.append(NSMutableAttributedString(string: " XEM):", attributes: [NSFontAttributeName: UIFont.systemFont(ofSize: 17)]))
        transactionAmountHeadingLabel.attributedText = amountAttributedString
    }
    
    /**
        Fetches the account data (balance, cosignatories, etc.) for the current account from the active NIS.
     
        - Parameter account: The current account for which the account data should get fetched.
     */
    fileprivate func fetchAccountData(forAccount account: Account) {
        
        nisProvider.request(NIS.accountData(accountAddress: account.address)) { [weak self] (result) in
            
            switch result {
            case let .success(response):
                
                do {
                    try response.filterSuccessfulStatusCodes()
                    
                    let json = JSON(data: response.data)
                    let accountData = try json.mapObject(AccountData.self)
                    
                    DispatchQueue.main.async {
                        
                        self?.accountData = accountData
                        self?.updateForm(withAccountData: accountData)
                    }
                    
                } catch {
                    
                    DispatchQueue.main.async {
                        
                        print("Failure: \(response.statusCode)")
                    }
                }
                
            case let .failure(error):
                
                DispatchQueue.main.async {
                    
                    print(error)
                }
            }
        }
    }
    
    /**
        Fetches the account data (balance, cosignatories, etc.) for the account from the active NIS.
     
        - Parameter accountAddress: The address of the account for which the account data should get fetched.
     */
    fileprivate func fetchAccountData(forAccountWithAddress accountAddress: String) {
        
        nisProvider.request(NIS.accountData(accountAddress: accountAddress)) { [weak self] (result) in
            
            switch result {
            case let .success(response):
                
                do {
                    try response.filterSuccessfulStatusCodes()
                    
                    let json = JSON(data: response.data)
                    let accountData = try json.mapObject(AccountData.self)
                    
                    DispatchQueue.main.async {
                        
                        self?.finishPreparingTransaction(withRecipientPublicKey: accountData.publicKey)
                    }
                    
                } catch {
                    
                    DispatchQueue.main.async {
                        
                        print("Failure: \(response.statusCode)")
                    }
                }
                
            case let .failure(error):
                
                DispatchQueue.main.async {
                    
                    print(error)
                }
            }
        }
    }
    
    /**
        Signs and announces a new transaction to the NIS.
     
        - Parameter transaction: The transaction object that should get signed and announced.
     */
    fileprivate func announceTransaction(_ transaction: Transaction) {
        
        let requestAnnounce = TransactionManager.sharedInstance.signTransaction(transaction, account: account!)
        
        nisProvider.request(NIS.announceTransaction(requestAnnounce: requestAnnounce)) { [weak self] (result) in
            
            switch result {
            case let .success(response):
                
                do {
                    try response.filterSuccessfulStatusCodes()
                    let responseJSON = JSON(data: response.data)
                    try self?.validateAnnounceTransactionResult(responseJSON)
                    
                    DispatchQueue.main.async {
                        
                        self?.showAlert(withMessage: "TRANSACTION_ANOUNCE_SUCCESS".localized())
                    }
                    
                } catch TransactionAnnounceValidation.failure(let errorMessage) {
                    
                    DispatchQueue.main.async {
                        
                        print("Failure: \(response.statusCode)")
                        self?.showAlert(withMessage: errorMessage)
                    }
                    
                } catch {
                    
                    DispatchQueue.main.async {
                        
                        print("Failure: \(response.statusCode)")
                        self?.showAlert(withMessage: "TRANSACTION_ANOUNCE_FAILED".localized())
                    }
                }
                
            case let .failure(error):
                
                DispatchQueue.main.async {
                    
                    print(error)
                    self?.showAlert(withMessage: "TRANSACTION_ANOUNCE_FAILED".localized())
                }
            }
        }
    }
    
    /**
        Validates the response (announce transaction result object) of the NIS
        regarding the announcement of the transaction.
     
        - Parameter responseJSON: The response of the NIS JSON formatted.
     
        - Throws:
        - TransactionAnnounceValidation.Failure if the announcement of the transaction wasn't successful.
     */
    fileprivate func validateAnnounceTransactionResult(_ responseJSON: JSON) throws {
        
        guard let responseCode = responseJSON["code"].int else { throw TransactionAnnounceValidation.failure(errorMessage: "TRANSACTION_ANOUNCE_FAILED".localized()) }
        let responseMessage = responseJSON["message"].stringValue
        
        switch responseCode {
        case 1:
            return
        default:
            throw TransactionAnnounceValidation.failure(errorMessage: responseMessage)
        }
    }
    
    /// Calculates the fee for the transaction and updates the transaction fee text field accordingly.
    fileprivate func calculateTransactionFee() {
        
        var transactionAmountString = transactionAmountTextField.text!.replacingOccurrences(of: " ", with: "")
        transactionAmountString = transactionAmountString.replacingOccurrences(of: ",", with: "")
        var transactionAmount = Double(transactionAmountString) ?? 0.0

        if transactionAmount < 0.000001 && transactionAmount != 0 {
            transactionAmountTextField.text = "0"
            transactionAmount = 0
        }

        var transactionFee = 0.0
        transactionFee = TransactionManager.sharedInstance.calculateFee(forTransactionWithAmount: transactionAmount)

        let transactionMessageByteArray = transactionMessageTextField.text!.hexadecimalStringUsingEncoding(String.Encoding.utf8)!.asByteArray()
        var transactionMessageLength = transactionMessageTextField.text!.hexadecimalStringUsingEncoding(String.Encoding.utf8)!.asByteArray().count
        if willEncrypt && transactionMessageLength != 0 {
            transactionMessageLength += 64
        }
        if transactionMessageLength != 0 {
            transactionFee += TransactionManager.sharedInstance.calculateFee(forTransactionWithMessage: transactionMessageByteArray)
        }

        let transactionFeeAttributedString = NSMutableAttributedString(string: "\("FEE".localized()): (\("MIN".localized()) ", attributes: [NSFontAttributeName: UIFont.systemFont(ofSize: 17)])
        transactionFeeAttributedString.append(NSMutableAttributedString(string: "\(Int(transactionFee))", attributes: [
            NSForegroundColorAttributeName: UIColor(red: 51.0/255.0, green: 191.0/255.0, blue: 86.0/255.0, alpha: 1.0),
            NSFontAttributeName: UIFont.systemFont(ofSize: 17)]))
        transactionFeeAttributedString.append(NSMutableAttributedString(string: " XEM)", attributes: [NSFontAttributeName: UIFont.systemFont(ofSize: 17)]))
        transactionFeeHeadingLabel.attributedText = transactionFeeAttributedString
        transactionFeeTextField.text = "\(Int(transactionFee))"
    }
    
    /**
        Finishes preparing the transaction and initiates the announcement of the final transaction.
     
        - Parameter recipientPublicKey: The public key of the transaction recipient.
     */
    fileprivate func finishPreparingTransaction(withRecipientPublicKey recipientPublicKey: String) {
        
        let transactionMessageText = transactionMessageTextField.text!.hexadecimalStringUsingEncoding(String.Encoding.utf8) ?? String()
        var transactionMessageByteArray: [UInt8] = transactionMessageText.asByteArray()
        
        if willEncrypt {
            var transactionEncryptedMessageByteArray: [UInt8] = Array(repeating: 0, count: 32)
            transactionEncryptedMessageByteArray = TransactionManager.sharedInstance.encryptMessage(transactionMessageByteArray, senderEncryptedPrivateKey: account!.privateKey, recipientPublicKey: recipientPublicKey)
            transactionMessageByteArray = transactionEncryptedMessageByteArray
        }
        
        if transactionMessageByteArray.count > 160 {
            showAlert(withMessage: "VALIDAATION_MESSAGE_LEANGTH".localized())
            return
        }
        
        let transactionMessage = Message(type: willEncrypt ? MessageType.encrypted : MessageType.unencrypted, payload: transactionMessageByteArray, message: transactionMessageTextField.text!)
        
        (preparedTransaction as! TransferTransaction).message = transactionMessage
        
        // Check if the transaction is a multisig transaction
        if activeAccountData!.publicKey != account!.publicKey {
            
            let multisigTransaction = MultisigTransaction(version: (preparedTransaction as! TransferTransaction).version, timeStamp: (preparedTransaction as! TransferTransaction).timeStamp, fee: Int(6 * 1000000), deadline: (preparedTransaction as! TransferTransaction).deadline, signer: account!.publicKey, innerTransaction: (preparedTransaction as! TransferTransaction))
            
            announceTransaction(multisigTransaction!)
            return
        }
        
        announceTransaction((preparedTransaction as! TransferTransaction))
    }
    
    final func setSuggestions() {
        let suggestions :[NEMTextField.Suggestion] = []
        
        //        let dataManager = CoreDataManager()
        //        for wallet in dataManager.getWallets() {
        //            let privateKey = HashManager.AES256Decrypt(wallet.privateKey, key: State.loadData!.password!)
        //            let account_address = AddressGenerator.generateAddressFromPrivateKey(privateKey!)
        //
        //            var find = false
        //
        //            for suggestion in suggestions {
        //                if suggestion.key == account_address {
        //                    find = true
        //                    break
        //                }
        //            }
        //            if !find {
        //                var sugest = NEMTextField.Suggestion()
        //                sugest.key = account_address
        //                sugest.value = account_address
        //                suggestions.append(sugest)
        //            }
        //
        //            find = false
        //
        //            for suggestion in suggestions {
        //                if suggestion.key == wallet.login {
        //                    find = true
        //                    break
        //                }
        //            }
        //            if !find {
        //                var sugest = NEMTextField.Suggestion()
        //                sugest.key = wallet.login
        //                sugest.value = account_address
        //                suggestions.append(sugest)
        //            }
        //        }
        
        // TODO: Disable whole address book don't handle public keys
        
        //        if AddressBookManager.isAllowed ?? false {
        //            for contact in AddressBookManager.contacts {
        //                var name = ""
        //                if contact.givenName != "" {
        //                    name = contact.givenName
        //                }
        //
        //                if contact.familyName != "" {
        //                    name += " " + contact.familyName
        //                }
        //
        //                for email in contact.emailAddresses{
        //                    if email.label == "NEM" {
        //                        let account_address = email.value as? String ?? " "
        //
        //                        var find = false
        //
        //                        for suggestion in suggestions {
        //                            if suggestion.key == account_address {
        //                                find = true
        //                                break
        //                            }
        //                        }
        //                        if !find {
        //                            var sugest = NEMTextField.Suggestion()
        //                            sugest.key = account_address
        //                            sugest.value = account_address
        //                            suggestions.append(sugest)
        //                        }
        //
        //                        find = false
        //
        //                        for suggestion in suggestions {
        //                            if suggestion.key == name {
        //                                find = true
        //                                break
        //                            }
        //                        }
        //                        if !find {
        //                            var sugest = NEMTextField.Suggestion()
        //                            sugest.key = name
        //                            sugest.value = account_address
        //                            suggestions.append(sugest)
        //                        }
        //                    }
        //                }
        //            }
        //        }
        
//        toAddressTextField.suggestions = suggestions
    }
    
    // MARK: - View Controller Outlet Actions
    
    @IBAction func chooseAccount(_ sender: UIButton) {
        
        if accountChooserViewController == nil {
            
            var accounts = accountData!.cosignatoryOf ?? []
            accounts.append(accountData!)
            
            let mainStoryboard = UIStoryboard(name: "Main", bundle: nil)
            let accountChooserViewController = mainStoryboard.instantiateViewController(withIdentifier: "AccountChooserViewController") as! AccountChooserViewController
            accountChooserViewController.view.frame = CGRect(x: view.frame.origin.x, y:  view.frame.origin.y, width: view.frame.width, height: view.frame.height)
            accountChooserViewController.view.layer.opacity = 0
            accountChooserViewController.delegate = self
            accountChooserViewController.accounts = accounts
            
            self.accountChooserViewController = accountChooserViewController
            
            if accounts.count > 0 {
                transactionSendButton.isEnabled = false
                view.addSubview(accountChooserViewController.view)
                
                UIView.animate(withDuration: 0.2, animations: {
                    accountChooserViewController.view.layer.opacity = 1
                })
            }
            
        } else {
            
            accountChooserViewController!.view.removeFromSuperview()
            accountChooserViewController!.removeFromParentViewController()
            accountChooserViewController = nil
        }
    }
    
    @IBAction func toggleEncryptionSetting(_ sender: UIButton) {
        
        willEncrypt = !willEncrypt
        sender.backgroundColor = (willEncrypt) ? UIColor(red: 90.0/255.0, green: 179.0/255.0, blue: 232.0/255.0, alpha: 1) : UIColor(red: 255.0/255.0, green: 255.0/255.0, blue: 255.0/255.0, alpha: 1)
        calculateTransactionFee()
    }
    
    @IBAction func createTransaction(_ sender: AnyObject) {
        
        guard transactionRecipientTextField.text != nil else { return }
        guard transactionAmountTextField.text != nil else { return }
        guard transactionMessageTextField.text != nil else { return }
        guard transactionFeeTextField.text != nil else { return }
        if activeAccountData == nil { activeAccountData = accountData }
        
        let transactionVersion = 1
        let transactionTimeStamp = Int(TimeManager.sharedInstance.timeStamp)
        let transactionAmount = Double(transactionAmountTextField.text!) ?? 0.0
        var transactionFee = Double(transactionFeeTextField.text!) ?? 0.0
        let transactionRecipient = transactionRecipientTextField.text!.replacingOccurrences(of: "-", with: "")
        let transactionMessageText = transactionMessageTextField.text!.hexadecimalStringUsingEncoding(String.Encoding.utf8) ?? String()
        let transactionMessageByteArray: [UInt8] = transactionMessageText.asByteArray()
        let transactionDeadline = Int(TimeManager.sharedInstance.timeStamp + waitTime)
        let transactionSigner = activeAccountData!.publicKey
        
        calculateTransactionFee()
        
        if transactionAmount < 0.000001 && transactionAmount != 0 {
            transactionAmountTextField!.text = "0"
            return
        }
        if transactionFee < Double(transactionFeeTextField.text!) {
            transactionFee = Double(transactionFeeTextField.text!)!
        }
        guard TransactionManager.sharedInstance.validateAccountAddress(transactionRecipient) else {
            showAlert(withMessage: "ACCOUNT_ADDRESS_INVALID".localized())
            return
        }
        guard (activeAccountData!.balance / 1000000) > transactionAmount else {
            showAlert(withMessage: "ACCOUNT_NOT_ENOUGHT_MONEY".localized())
            return
        }
        guard TransactionManager.sharedInstance.validateHexadecimalString(transactionMessageText) == true else {
            showAlert(withMessage: "NOT_A_HEX_STRING".localized())
            return
        }
        if willEncrypt {
            if transactionMessageByteArray.count > 112 {
                showAlert(withMessage: "VALIDAATION_MESSAGE_LEANGTH".localized())
                return
            }
        } else {
            if transactionMessageByteArray.count > 160 {
                showAlert(withMessage: "VALIDAATION_MESSAGE_LEANGTH".localized())
                return
            }
        }
        
        let transaction = TransferTransaction(version: transactionVersion, timeStamp: transactionTimeStamp, amount: transactionAmount * 1000000, fee: Int(transactionFee * 1000000), recipient: transactionRecipient, message: nil, deadline: transactionDeadline, signer: transactionSigner!)
        
        preparedTransaction = transaction
        
        fetchAccountData(forAccountWithAddress: transactionRecipient)
    }
    
    @IBAction func textFieldEditingChanged(_ sender: UITextField) {
        calculateTransactionFee()
    }
    
    @IBAction func textFieldReturnKeyToched(_ sender: UITextField) {
        
        switch sender {
        case transactionRecipientTextField:
            transactionAmountTextField.becomeFirstResponder()
        case transactionAmountTextField :
            transactionMessageTextField.becomeFirstResponder()
        case transactionMessageTextField :
            transactionFeeTextField.becomeFirstResponder()
        default :
            sender.becomeFirstResponder()
        }
        
        calculateTransactionFee()
    }
    
    @IBAction func textFieldEditingEnd(_ sender: UITextField) {
        calculateTransactionFee()
    }
    
    @IBAction func endTyping(_ sender: NEMTextField) {
        
        calculateTransactionFee()
        sender.becomeFirstResponder()
    }
    
    @IBAction func cancel(_ sender: UIBarButtonItem) {
        dismiss(animated: true, completion: nil)
    }
}

// MARK: - Account Chooser Delegate

extension TransactionSendViewController: AccountChooserDelegate {
    
    func didChooseAccount(_ accountData: AccountData) {
        
        activeAccountData = accountData
        
        accountChooserViewController?.view.removeFromSuperview()
        accountChooserViewController?.removeFromParentViewController()
        accountChooserViewController = nil
        
        transactionSendButton.isEnabled = true
        transactionEncryptionButton.isEnabled = activeAccountData?.address == self.accountData?.address
        
        if activeAccountData?.address != self.accountData?.address {
            willEncrypt = false
            transactionEncryptionButton.backgroundColor = UIColor(red: 255.0/255.0, green: 255.0/255.0, blue: 255.0/255.0, alpha: 1)
        }
    }
}

// MARK: - Navigation Bar Delegate

extension TransactionSendViewController: UINavigationBarDelegate {
    
    func position(for bar: UIBarPositioning) -> UIBarPosition {
        return .topAttached
    }
}
