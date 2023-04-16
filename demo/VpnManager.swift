let kProxyServiceVPNStatusNotification = Notification.Name(rawValue:"kProxyServiceVPNStatusNotification")

import Foundation
import NetworkExtension
import UIKit
enum VPNStatus {
    case off
    case connecting
    case on
    case disconnecting
}

class VpnManager{
    
    public var host: String = ""
    public var port: Int = 0
    public var name: String = ""
    public var password: String = ""
    public var dns: String = ""
    public var endtime: TimeInterval = 0
   var tunnel: NETunnelProviderManager!
    private var vpnManager: NETunnelProviderManager!
    static let shared = VpnManager()
    var observerAdded: Bool = false
    var tunnelDeviceIp: String = "10.8.0.1"
    var tunnelFakeIp: String = "10.8.0.2"
    var tunnelSubnetMask: String = "255.255.255.0"
    fileprivate(set) var vpnStatus = VPNStatus.off {
        didSet {
            NotificationCenter.default.post(name: kProxyServiceVPNStatusNotification, object: nil)
        }
    }
    
    init() {
        loadProviderManager{
            guard let manager = $0 else{return}
            self.updateVPNStatus(manager)
        }
        addVPNStatusObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func addVPNStatusObserver() {
        guard !observerAdded else{
            return
        }
        loadProviderManager { [unowned self] (manager) -> Void in
            if let manager = manager {
                self.observerAdded = true
                NotificationCenter.default.addObserver(forName: NSNotification.Name.NEVPNStatusDidChange, object: manager.connection, queue: OperationQueue.main, using: { [unowned self] (notification) -> Void in
                    self.updateVPNStatus(manager)
                })
            }
        }
    }
    
    func updateVPNStatus(_ manager: NEVPNManager) {
        switch manager.connection.status {
        case .connected:
            self.vpnStatus = .on
        case .connecting, .reasserting:
            self.vpnStatus = .connecting
        case .disconnecting:
            self.vpnStatus = .disconnecting
        case .disconnected, .invalid:
            self.vpnStatus = .off
        @unknown default: break
            
        }
        print(self.vpnStatus)
    }
}

// load VPN Profiles
extension VpnManager{

    fileprivate func createProviderManager() -> NETunnelProviderManager {
//        let manager = NETunnelProviderManager()
//        let conf = NETunnelProviderProtocol()
//        conf.providerBundleIdentifier = "com.memory.wt.Jitterbug.JitterbugTunnel"
//
//        conf.serverAddress = "127.0.0.1"
//        manager.protocolConfiguration = conf
//        manager.localizedDescription = "demo"
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "demo"
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.memory.wt.Jitterbug.JitterbugTunnel"
        proto.serverAddress = ""
        manager.protocolConfiguration = proto
        manager.isEnabled = true
        
        return manager
    }
    func backgroundTask(message: String?, task: @escaping () throws -> Void, onComplete: @escaping () -> Void = {}) {
        DispatchQueue.main.async {
//            self.busy = true
//            self.busyMessage = message
            DispatchQueue.global(qos: .background).async {
                #if canImport(UIKit)
                let app = UIApplication.shared
                let bgtask = app.beginBackgroundTask()
                #endif
                defer {
                    #if canImport(UIKit)
                    app.endBackgroundTask(bgtask)
                    #endif
                    DispatchQueue.main.async {
//                        self.busy = false
//                        self.busyMessage = nil
                        onComplete()
                    }
                }
                do {
                    try task()
                } catch {
                    DispatchQueue.main.async {
                        print(error.localizedDescription)
//                        self.alertMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    private func initTunnel(onSuccess: (() -> ())? = nil) {
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            if error == nil {
//                DispatchQueue.main.async {
                    print("initTunnel(onSuccess")
//                }
            }
            if !(managers?.isEmpty ?? true), let manager = managers?[0] {
                self.vpnManager = manager
                onSuccess?()
            }
        }
    }
    func loadAndCreatePrividerManager(_ complete: @escaping (NETunnelProviderManager?) throws -> Void ){
        NETunnelProviderManager.loadAllFromPreferences{(managers, error) in
            guard let managers = managers else{return}
            let manager: NETunnelProviderManager
            if managers.count > 0 {
                manager = managers[0]
                self.delDupConfig(managers)
            }else{
                manager = self.createProviderManager()
            }
            
            manager.isEnabled = true
//            self.setRulerConfig(manager)
            var success = false
            self.backgroundTask(message:"Setting up VPN tunnel...") {
                let lock = DispatchSemaphore(value: 0)
                var error: Error?
                manager.saveToPreferences { err in
                    error = err
                    lock.signal()
                }
                lock.wait()
                if let err = error {
                    throw err
                } else {
                    success = true
                }
            } onComplete: {
                if success {
                    self.initTunnel {
                        do {
                            try complete(self.vpnManager)

                        }catch {
                            
                        }
                    }
                }
            }
//            manager.saveToPreferences{
//                if ($0 != nil){
//                }
//                manager.loadFromPreferences{
//                    if $0 != nil{
//                        print($0.debugDescription)
//                        complete(nil);return;
//                    }
//                    self.tunnel = manager
//
//                    self.addVPNStatusObserver()
//
//                    complete(manager)
//                }
//            }
            
        }
    }
    
    func loadProviderManager(_ complete: @escaping (NETunnelProviderManager?) -> Void){
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            if let managers = managers {
                if managers.count > 0 {
                    let manager = managers[0]
                    complete(manager)
                    return
                }
            }
            complete(nil)
        }
    }
    
    
    func delDupConfig(_ arrays:[NETunnelProviderManager]){
        if (arrays.count)>1{
            for i in 0 ..< arrays.count{
                arrays[i].removeFromPreferences(completionHandler: { (error) in
                    if(error != nil){print(error.debugDescription)}
                })
            }
        }
    }
}

// Actions
extension VpnManager{
    func connect(){
        self.loadAndCreatePrividerManager { (manager) in
            guard let manager = manager else{return}
         
//                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 3) {
//                    do{
//                    try manager.connection.startVPNTunnel(options: [:])
//                }catch let err{
//                    self.vpnStatus = .off
//                    print(err)
//                }
//                }
            
            let lock = DispatchSemaphore(value: 0)
//            self.vpnObserver = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: manager.connection, queue: nil, using: { [weak self] _ in
//                guard let _self = self else {
//                    return
//                }
//                print("[VPN] Connected? \(manager.connection.status == .connected)")
//                _self.setTunnelStarted(manager.connection.status == .connected, signallingLock: lock)
//            })
            let options = ["TunnelDeviceIP": self.tunnelDeviceIp as NSObject,
                           "TunnelFakeIP": self.tunnelFakeIp as NSObject,
                           "TunnelSubnetMask": self.tunnelSubnetMask as NSObject]
            do {
                try manager.connection.startVPNTunnel(options: options)
            } catch NEVPNError.configurationDisabled {
                 print("Jitterbug VPN has been disabled in settings or another VPN configuration is selected.")
            }
            if lock.wait(timeout: .now() + .seconds(15)) == .timedOut {
                print (String("Failed to start tunnel."))
            }
           
        }
    }
    
    func disconnect(){
        loadProviderManager{
            $0?.connection.stopVPNTunnel()
        }
    }
}

// Generate and Load ConfigFile
extension VpnManager{
    
    fileprivate func setRulerConfig(_ manager:NETunnelProviderManager){
        
        var conf = [String:AnyObject]()
        conf["ss_host"] = host as AnyObject?
        conf["ss_port"] = port as AnyObject?
        conf["ss_name"] = name as AnyObject?
        conf["ss_dns"]  = dns  as AnyObject?
        conf["ss_time"] = endtime as AnyObject?
        conf["ss_pwd"]  = password as AnyObject?
        let orignConf = manager.protocolConfiguration as! NETunnelProviderProtocol
        orignConf.providerConfiguration = conf
        manager.protocolConfiguration = orignConf
    }
}
