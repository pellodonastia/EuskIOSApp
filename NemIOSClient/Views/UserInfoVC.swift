import UIKit

class UserInfoVC: AbstractViewController
{

//    @IBOutlet weak var qrImg: UIImageView!
//    @IBOutlet weak var keyLable: UILabel!
    
    @IBOutlet weak var qrImageView: UIImageView!
    @IBOutlet weak var userAddress: UILabel!
    @IBOutlet weak var userName: UITextField!
    
    private var address :String!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        State.fromVC = SegueToUserInfo
        State.currentVC = SegueToUserInfo
        
        let privateKey = HashManager.AES256Decrypt(State.currentWallet!.privateKey)
        let publicKey = KeyGenerator.generatePublicKey(privateKey)
        address = AddressGenerator.generateAddress(publicKey)
        
        userAddress.text = address
        userName.placeholder = State.currentWallet!.login
        
        _generateQR()
    }
    @IBAction func nameChanged(sender: AnyObject) {
        userName.becomeFirstResponder()
        
        _generateQR()
    }
    
    @IBAction func copyAddress(sender: AnyObject) {
        let pasteBoard :UIPasteboard = UIPasteboard.generalPasteboard()
        pasteBoard.string = address

    }
    
    @IBAction func shareAddress(sender: AnyObject) {
        
    }
    
    @IBAction func copyQR(sender: AnyObject) {
        let pasteBoard :UIPasteboard = UIPasteboard.generalPasteboard()
        pasteBoard.string = (Validate.stringNotEmpty(userName.text) ? userName.text! : State.currentWallet!.login) + ": " + address
    }
    
    @IBAction func shareQR(sender: AnyObject) {
        
    }
    
    private final func _normalize(text: String) -> String {
        var newString = ""
        for var i = 0 ; i < text.characters.count ; i+=4 {
            let substring = (text as NSString).substringWithRange(NSRange(location: i, length: 4))
            newString += substring + "-"
        }
        let length :Int = newString.characters.count - 1
        return (newString as NSString).substringWithRange(NSRange(location: 0, length: length))
    }
    
    private final func _generateQR()
    {
        let userDictionary: [String : String] = [
            QRKeys.Adress.rawValue : address,
            QRKeys.Name.rawValue : Validate.stringNotEmpty(userName.text) ? userName.text! : State.currentWallet!.login
        ]
        
        let jsonDictionary :NSDictionary = NSDictionary(objects: [1, userDictionary], forKeys: [QRKeys.DataType.rawValue, QRKeys.Data.rawValue])
        
        let jsonData :NSData = try! NSJSONSerialization.dataWithJSONObject(jsonDictionary, options: NSJSONWritingOptions())
        
        let base64String :String = jsonData.base64EncodedStringWithOptions(NSDataBase64EncodingOptions())
        let qr :QR = QR()
        qrImageView.image =  qr.createQR(base64String)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

    }
}
