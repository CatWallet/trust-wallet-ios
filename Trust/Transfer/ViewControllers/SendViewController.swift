// Copyright DApps Platform Inc. All rights reserved.

import Foundation
import UIKit
import Eureka
import JSONRPCKit
import APIKit
import BigInt
import QRCodeReaderViewController
import TrustCore
import TrustKeystore
import RealmSwift

protocol SendViewControllerDelegate: class {
    func didPressConfirm(
        transaction: UnconfirmedTransaction,
        transferType: TransferType,
        in viewController: SendViewController
    )
}
class SendViewController: FormViewController {
    let contact = Contact()
    var getData:[MyStruct] = []
    var mystruct: MyStruct?
    private lazy var viewModel: SendViewModel = {
        return .init(transferType: transferType, config: session.config, chainState: session.chainState, storage: storage, balance: session.balance)
    }()
    weak var delegate: SendViewControllerDelegate?
    struct Values {
        static let address = "address"
        static let contact = "contact"
        static let amount = "amount"
        static let collectible = "collectible"
    }
    let session: WalletSession
    let account: Account
    let transferType: TransferType
    let storage: TokensDataStore
    var addressRow: TextFloatLabelRow? {
        return form.rowBy(tag: Values.address) as? TextFloatLabelRow
    }
    var contactRow: TextFloatLabelRow? {
        return form.rowBy(tag: Values.contact) as? TextFloatLabelRow
    }
    var amountRow: TextFloatLabelRow? {
        return form.rowBy(tag: Values.amount) as? TextFloatLabelRow
    }
    lazy var maxButton: UIButton = {
        let button = Button(size: .normal, style: .borderless)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(NSLocalizedString("send.max.button.title", value: "Max", comment: ""), for: .normal)
        button.addTarget(self, action: #selector(useMaxAmount), for: .touchUpInside)
        return button
    }()
    private var allowedCharacters: String = {
        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        return "0123456789" + decimalSeparator
    }()
    private var data = Data()
    init(
        session: WalletSession,
        storage: TokensDataStore,
        account: Account,
        transferType: TransferType = .ether(destination: .none)
    ) {
        self.session = session
        self.account = account
        self.transferType = transferType
        self.storage = storage
        super.init(nibName: nil, bundle: nil)
        title = viewModel.title
        view.backgroundColor = viewModel.backgroundColor

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: R.string.localizable.next(),
            style: .done,
            target: self,
            action: #selector(send)
        )

        let section = Section(header: "", footer: viewModel.isFiatViewHidden() ? "" : viewModel.pairRateRepresantetion())
        fields().forEach { cell in
            section.append(cell)
        }
        form = Section()
            +++ section
            +++ Section()
            <<< TextAreaRow() {
                $0.placeholder = "Add noted"
                $0.textAreaHeight = .dynamic(initialTextViewHeight: 110)
            }
    }

    override func viewWillAppear(_ animated: Bool) {
        getContacts()
        super.viewWillAppear(animated)
        self.navigationController?.applyTintAdjustment()
    }

    private func fields() -> [BaseRow] {
        return viewModel.views.map { field(for: $0) }
    }
    
    private func field(for type: SendViewType) -> BaseRow {
        getContacts()
        switch type {
        case .savedContact:
            return PushRow<MyStruct>("Choose contact") {
                    $0.title = $0.tag
                    $0.options = getData
                    $0.value = mystruct
                    $0.displayValueFor = {
                    guard let person = $0 else { return nil }
                    return person.name
                }
                    }.onPresent({ (_, vc) in
                        vc.enableDeselection = false
                        vc.dismissOnSelection = false
                    })
                .cellUpdate({ [self] (cell, row ) in
                        let address = self.form.rowBy(tag: Values.address) as! RowOf<String>
                        address.value = row.value?.address
                        address.updateCell()
                    })
        case .address:
            return addressField()
        case .switchR:
            return SwitchRow("switchRowTag"){
                $0.title = "Add contact"
            }
        case .contact:
            return contactField()
        case .amount:
            return amountField()
        case .collectible(let token):
            return collectibleField(with: token)
        }
    }

    func addressField() -> TextFloatLabelRow {
        let recipientRightView = FieldAppereance.addressFieldRightView(
            pasteAction: { [unowned self] in self.pasteAction() },
            qrAction: { [unowned self] in self.openReader() }
        )
        return AppFormAppearance.textFieldFloat(tag: Values.address) {
            $0.add(rule: EthereumAddressRule())
            $0.validationOptions = .validatesOnDemand
        }.cellUpdate { cell, _ in
            cell.textField.textAlignment = .left
            cell.textField.placeholder = NSLocalizedString("send.recipientAddress.textField.placeholder", value: "Recipient Address", comment: "")
            cell.textField.rightView = recipientRightView
            cell.textField.rightViewMode = .always
            cell.textField.accessibilityIdentifier = "amount-field"
            cell.textField.keyboardType = .default
            cell.textField.autocorrectionType = UITextAutocorrectionType.no
        }
    }
    
    func contactField() -> TextFloatLabelRow {
        let recipientRightView = FieldAppereance.contactFieldRightView (
            pasteAction: { [unowned self] in self.pasteAction() }
        )
        return AppFormAppearance.textFieldFloat(tag: Values.contact) {
            $0.validationOptions = .validatesOnDemand
            $0.hidden = Condition.function(["switchRowTag"], { form in
                return !((form.rowBy(tag: "switchRowTag") as? SwitchRow)?.value ?? false)
            })
            $0.title = "Add Contact!"
            }.cellUpdate { cell, _ in
                cell.textField.textAlignment = .left
                cell.textField.placeholder = NSLocalizedString("send.contactName.textField.placeholder", value: "Contact Name", comment: "")
                cell.textField.rightView = recipientRightView
                cell.textField.rightViewMode = .always
                cell.textField.accessibilityIdentifier = "contact-field"
                cell.textField.keyboardType = .default
                cell.textField.autocorrectionType = UITextAutocorrectionType.no
        }
    }

    func amountField() -> TextFloatLabelRow {
        let fiatButton = Button(size: .normal, style: .borderless)
        fiatButton.translatesAutoresizingMaskIntoConstraints = false
        fiatButton.setTitle(viewModel.currentPair.right, for: .normal)
        fiatButton.addTarget(self, action: #selector(fiatAction), for: .touchUpInside)
        fiatButton.isHidden = viewModel.isFiatViewHidden()
        let amountRightView = UIStackView(arrangedSubviews: [
            maxButton,
            fiatButton,
        ])
        amountRightView.translatesAutoresizingMaskIntoConstraints = false
        amountRightView.distribution = .equalSpacing
        amountRightView.spacing = 1
        amountRightView.axis = .horizontal
        return AppFormAppearance.textFieldFloat(tag: Values.amount) {
            $0.add(rule: RuleRequired())
            $0.validationOptions = .validatesOnDemand
        }.cellUpdate {[weak self] cell, _ in
            cell.textField.isCopyPasteDisabled = true
            cell.textField.textAlignment = .left
            cell.textField.delegate = self
            cell.textField.placeholder = "\(self?.viewModel.currentPair.left ?? "") " + NSLocalizedString("send.amount.textField.placeholder", value: "Amount", comment: "")
            cell.textField.keyboardType = .decimalPad
            cell.textField.rightView = amountRightView
            cell.textField.rightViewMode = .always
        }
    }

    func collectibleField(with token: NonFungibleTokenObject) -> SendNFTRow {
        let cell = SendNFTRow(tag: Values.collectible)
        let viewModel = NFTDetailsViewModel(token: token)
        cell.cellSetup { cell, _ in
            cell.tokenImage.kf.setImage(
                with: viewModel.imageURL,
                placeholder: viewModel.placeholder
            )
            cell.label.text = viewModel.title
        }
        return cell
    }

    func clear() {
        let fields = [addressRow, amountRow]
        for field in fields {
            field?.value = ""
            field?.reload()
        }
    }
    
    func addNewContact(_ name: String, _ address: String){
        let realm = try! Realm()
        contact.address = address
        contact.name = name
        try! realm.write {
            realm.add(contact)
        }
    }
    
    func deleteContact(){
        let realm = try! Realm()
        try! realm.write {
            realm.delete(realm.objects(Contact.self))
        }
    }
    
    func getContacts(){
        let people = try! Realm().objects(Contact.self)
        for person in people{
            getData.append(MyStruct(name: person.name!, address: person.address!))
        }
    }

    @objc func send() {
        let errors = form.validate()
        guard errors.isEmpty else { return }
        let addressString = addressRow?.value?.trimmed ?? ""
        let amountString = viewModel.amount
        guard let address = Address(string: addressString) else {
            return displayError(error: Errors.invalidAddress)
        }
        let parsedValue: BigInt? = {
            switch transferType {
            case .ether, .dapp, .nft:
                return EtherNumberFormatter.full.number(from: amountString, units: .ether)
            case .token(let token):
                return EtherNumberFormatter.full.number(from: amountString, decimals: token.decimals)
            }
        }()
        guard let value = parsedValue else {
            return displayError(error: SendInputErrors.wrongInput)
        }
        if let name = contactRow?.value {
            addNewContact(name, addressString)
        }
        
        let transaction = UnconfirmedTransaction(
            transferType: transferType,
            value: value,
            to: address,
            data: data,
            gasLimit: .none,
            gasPrice: viewModel.gasPrice,
            nonce: .none
        )
        self.delegate?.didPressConfirm(transaction: transaction, transferType: transferType, in: self)
    }
    @objc func openReader() {
        let controller = QRCodeReaderViewController()
        controller.delegate = self
        present(controller, animated: true, completion: nil)
    }
    @objc func pasteAction() {
        guard let value = UIPasteboard.general.string?.trimmed else {
            return displayError(error: SendInputErrors.emptyClipBoard)
        }

        guard CryptoAddressValidator.isValidAddress(value) else {
            return displayError(error: Errors.invalidAddress)
        }
        addressRow?.value = value
        addressRow?.reload()
        activateAmountView()
    }
    @objc func useMaxAmount() {
        amountRow?.value = viewModel.sendMaxAmount()
        updatePriceSection()
        amountRow?.reload()
    }
    @objc func fiatAction(sender: UIButton) {
        let swappedPair = viewModel.currentPair.swapPair()
        //New pair for future calculation we should swap pair each time we press fiat button.
        viewModel.currentPair = swappedPair
        //Update button title.
        sender.setTitle(viewModel.currentPair.right, for: .normal)
        //Hide max button
        maxButton.isHidden = viewModel.isMaxButtonHidden()
        //Reset amountRow value.
        amountRow?.value = nil
        amountRow?.reload()
        //Reset pair value.
        viewModel.pairRate = 0.0
        //Update section.
        updatePriceSection()
        //Set focuse on pair change.
        activateAmountView()
    }
    func activateAmountView() {
        amountRow?.cell.textField.becomeFirstResponder()
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    private func updatePriceSection() {
        //Update section only if fiat view is visible.
        guard !viewModel.isFiatViewHidden() else {
            return
        }
        //We use this section update to prevent update of the all section including cells.
        UIView.setAnimationsEnabled(false)
        tableView.beginUpdates()
        if let containerView = tableView.footerView(forSection: 1) {
            containerView.textLabel!.text = viewModel.pairRateRepresantetion()
            containerView.sizeToFit()
        }
        tableView.endUpdates()
        UIView.setAnimationsEnabled(true)
    }
}
extension SendViewController: QRCodeReaderDelegate {
    func readerDidCancel(_ reader: QRCodeReaderViewController!) {
        reader.stopScanning()
        reader.dismiss(animated: true, completion: nil)
    }
    func reader(_ reader: QRCodeReaderViewController!, didScanResult result: String!) {
        reader.stopScanning()
        reader.dismiss(animated: true) { [weak self] in
           self?.activateAmountView()
        }

        guard let result = QRURLParser.from(string: result) else { return }
        addressRow?.value = result.address
        addressRow?.reload()

        if let dataString = result.params["data"] {
            data = Data(hex: dataString.drop0x)
        } else {
            data = Data()
        }

        if let value = result.params["amount"] {
            amountRow?.value = EtherNumberFormatter.full.string(from: BigInt(value) ?? BigInt(), units: .ether)
        } else {
            amountRow?.value = ""
        }
        amountRow?.reload()
        viewModel.pairRate = 0.0
        updatePriceSection()
    }
}
extension SendViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let input = textField.text else {
            return true
        }
        //In this step we validate only allowed characters it is because of the iPad keyboard.
        let characterSet = NSCharacterSet(charactersIn: self.allowedCharacters).inverted
        let separatedChars = string.components(separatedBy: characterSet)
        let filteredNumbersAndSeparator = separatedChars.joined(separator: "")
        if string != filteredNumbersAndSeparator {
            return false
        }
        //This is required to prevent user from input of numbers like 1.000.25 or 1,000,25.
        if string == "," || string == "." ||  string == "'" {
            return !input.contains(string)
        }
        //Total amount of the user input.
        let stringAmount = (input as NSString).replacingCharacters(in: range, with: string)
        //Convert to deciaml for pair rate update.
        let amount = viewModel.decimalAmount(with: stringAmount)
        //Update of the pair rate.
        viewModel.updatePairPrice(with: amount)
        updatePriceSection()
        //Update of the total amount.
        viewModel.updateAmount(with: stringAmount)
        return true
    }
}
