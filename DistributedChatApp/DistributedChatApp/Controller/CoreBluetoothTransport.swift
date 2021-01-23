//
//  CoreBluetoothTransport.swift
//  DistributedChatApp
//
//  Created by Fredrik on 1/22/21.
//

import CoreBluetooth
import Combine
import DistributedChat
import Foundation
import Logging

fileprivate let log = Logger(label: "CoreBluetoothTransport")

/// Custom UUID specifically for the 'Distributed Chat' service
fileprivate let serviceUUID = CBUUID(string: "59553ceb-2ffa-4018-8a6c-453a5292044d")
/// Custom UUID for the (write-only) message inbox characteristic
fileprivate let characteristicUUID = CBUUID(string: "440a594c-3cc2-494a-a08a-be8dd23549ff")

class CoreBluetoothTransport: NSObject, ChatTransport, CBPeripheralManagerDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var peripheralManager: CBPeripheralManager!
    private var centralManager: CBCentralManager!
    
    private var initialized: Bool = false
    private var listeners = [(String) -> Void]()
    
    private let settings: Settings
    private var settingsSubscription: AnyCancellable?
    
    /// Tracks remote peripherals discovered by the central that feature our service's
    /// GATT characteristic. Note that out-of-range peripherals are not automatically
    /// removed, this happens first after unsuccessful attempt to send a message to it.
    private var nearbyPeripherals: [CBPeripheral: CBCharacteristic] = [:]
    
    required init(settings: Settings) {
        self.settings = settings
        super.init()
        
        // The app acts both as a peripheral (for receiving messages via an
        // exposed, writable GATT characteristic) and a central (for sending messages
        // and discovering nearby devices).
        
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        settingsSubscription = settings.$bluetoothAdvertisingEnabled.sink { [unowned self] in
            if $0 {
                startAdvertising()
            } else {
                stopAdvertising()
            }
        }
    }
    
    func broadcast(_ raw: String) {
        // TODO
    }
    
    func onReceive(_ handler: @escaping (String) -> Void) {
        listeners.append(handler)
    }
    
    // MARK: Peripheral implementation
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            log.info("Peripheral is powered on!")
            
            if !initialized {
                initialized = true
                publishService()
            } else if settings.bluetoothAdvertisingEnabled {
                startAdvertising()
            }
        case .poweredOff:
            log.info("Peripheral is powered off!")
        default:
            // TODO: Handle other states
            log.info("Peripheral switched into state \(peripheral.state)")
            break
        }
    }
    
    private func publishService() {
        log.info("Publishing DistributedChat GATT service...")
        
        let service = CBMutableService(type: serviceUUID, primary: true)
        let characteristic = CBMutableCharacteristic(type: characteristicUUID,
                                                     properties: [.write],
                                                     value: nil,
                                                     permissions: [.writeable])
        
        service.characteristics = [characteristic]
        peripheralManager.add(service)
        
        startAdvertising()
    }
    
    private func startAdvertising() {
        log.info("Starting to advertise")
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "DistributedChat"
        ])
    }
    
    private func stopAdvertising() {
        log.info("Stopping advertisting")
        peripheralManager.stopAdvertising()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            // TODO: Deal with offset?
            if let data = request.value, let str = String(data: data, encoding: .utf8) {
                log.info("Received write to inbox: '\(str)'")
                
                for listener in listeners {
                    listener(str)
                }
                
                peripheralManager.respond(to: request, withResult: .success)
            }
        }
    }
    
    // MARK: Central implementation
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log.info("Central is powered on, scanning for peripherals!")
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        default:
            // TODO: Handle other states
            log.info("Central switched into state \(central.state)")
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        log.info("Discovered remote peripheral \(peripheral.name ?? "?") with advertised name \(advertisementData[CBAdvertisementDataLocalNameKey] ?? "?") (RSSI: \(rssi)")
        
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        log.debug("Discovered services on remote peripheral")
        
        if let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) {
            log.info("Found our DistributedChat service on the remote peripheral, looking for characteristic...")
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        log.debug("Discovered characteristics on remote peripheral")
        
        if let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID }) {
            log.info("Found our DistributedChat characteristic on the remote peripheral, nice!")
            nearbyPeripherals[peripheral] = characteristic
        }
    }
}