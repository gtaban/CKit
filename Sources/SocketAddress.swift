
//  Copyright (c) 2016, Yuji
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
//  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
//  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
//  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
//  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//  The views and conclusions contained in the software and documentation are those
//  of the authors and should not be interpreted as representing official policies,
//  either expressed or implied, of the FreeBSD Project.
//
//  Created by yuuji on 6/2/16.
//  Copyright © 2016 yuuji. All rights reserved.
//

#if os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
    public let UNIX_PATH_MAX = 104
#elseif os(FreeBSD) || os(Linux)
    public let UNIX_PATH_MAX = 108
#endif


public struct SocketAddress {
    #if !os(Linux)
    var storage: _sockaddr_storage
    #else
    var storage: _sockaddr_storage
    #endif
    public init(storage: _sockaddr_storage) {
        self.storage = storage
    }
}

// MARK: CustomStringConvertible
extension SocketAddress : CustomStringConvertible {
    public var description: String {
        let family = "\(self.type)"
        var detail = ""
        switch self.type {
        case .inet, .inet6:
            detail = "\(ip!):\(port!)"
        default:
            return family
        }
        return family + " " + detail
    }
}

// MARK: Initializers
extension SocketAddress {
    
    public init(addr: UnsafePointer<sockaddr>, port: in_port_t? = nil) {
        self.storage = _sockaddr_storage()
        #if !os(Linux)
//        memcpy(mutablePointer(of: &self.storage).mutableRawPointer, addr.rawPointer, Int(addr.pointee.sa_len))
            let len = Int(addr.pointee.sa_len)
        #else
            var len = MemoryLayout<sockaddr>.size
            
            switch SocketDomains(rawValue: addr.pointee.sa_family)! {
            case .inet:
                len = MemoryLayout<sockaddr_in>.size
                
            case .inet6:
                len = MemoryLayout<sockaddr_in6>.size
                
            case .unix:
                len = MemoryLayout<sockaddr_un>.size

            case .link:
                len = MemoryLayout<sockaddr_dl>.size

            default:
                break
            }

            memcpy(mutablePointer(of: &self.storage).mutableRawPointer, addr.rawPointer, len)
        #endif
        
        mutablePointer(of: &self.storage)
            .mutableRawPointer.copyBytes(from: addr.rawPointer, count: len)
        
        if let port = port {
            switch SocketFamilies(rawValue: addr.pointee.sa_family)! {
            case .inet:
                mutablePointer(of: &self.storage).cast(to: sockaddr_in.self).pointee.sin_port = port.byteSwapped
            case .inet6:
                mutablePointer(of: &self.storage).cast(to: sockaddr_in6.self).pointee.sin6_port = port.byteSwapped
            default: break
            }
        }
    }

    public init?(domain: SocketFamilies, port: in_port_t) {
        switch domain {
        case .inet:
            self.storage = _sockaddr_storage()
            let addr = sockaddr_in(port: port)
            mutablePointer(of: &self.storage)
                .cast(to: sockaddr_in.self)
                .initialize(to: addr)
            
        case .inet6:
            self.storage = _sockaddr_storage()
            let addr = sockaddr_in6(port: port)
            mutablePointer(of: &self.storage)
                .cast(to: sockaddr_in6.self)
                .initialize(to: addr)

        default:
            return nil
        }
    }
    
    public init?(ip: String, domain: SocketFamilies, port: in_port_t = 0) {
        switch domain {
        case .inet:
            self.storage = _sockaddr_storage()
            var addr = sockaddr_in(port: port)
            _ = ip.withCString {
                inet_pton(AF_INET, $0,
                          mutablePointer(of: &(addr.sin_addr)).mutableRawPointer)
            }
            mutablePointer(of: &self.storage)
                .cast(to: sockaddr_in.self)
                .initialize(to: addr)
            
        case .inet6:
            self.storage = _sockaddr_storage()
            var addr = sockaddr_in6(port: port)
            _ = ip.withCString {
                inet_pton(AF_INET6, $0,
                          mutablePointer(of: &(addr.sin6_addr)).mutableRawPointer)
            }
            mutablePointer(of: &self.storage)
                .cast(to: sockaddr_in6.self)
                .initialize(to: addr)
            
        default:
            return nil
        }
    }
    
    public init?(unixPath: String) {
        self.storage = _sockaddr_storage()
        self.storage.ss_family = sa_family_t(AF_UNIX)
        #if !os(Linux)
        self.storage.ss_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        strncpy(mutablePointer(of: &(self.storage.__ss_pad1)).cast(to: Int8.self),
                unixPath.cString(using: .utf8)!,
                UNIX_PATH_MAX)
    }
    
    #if !os(Linux)
    public init?(linkAddress: String) {
        self.storage = _sockaddr_storage()
        self.storage.ss_family = sa_family_t(AF_LINK)
        self.storage.ss_len = UInt8(MemoryLayout<sockaddr_un>.size)
        link_addr(linkAddress.cString(using: .ascii), mutablePointer(of: &self.storage).cast(to: sockaddr_dl.self))
    }
    #endif
}

extension SocketAddress {
    
    @available(*, renamed: "socklen", deprecated, message: "use socklen instead")
    public var len: socklen_t {
        return socklen_t(storage.ss_len)
    }
    
    @available(*, renamed: "family")
    public var type: SocketFamilies {
        return SocketFamilies(rawValue: storage.ss_family)!
    }
    
    public var family: SocketFamilies {
        return SocketFamilies(rawValue: storage.ss_family)!
    }
    
    public func addr() -> sockaddr {
        return unsafeCast(of: self.storage, cast: sockaddr.self)
    }
    
    public func inet() -> sockaddr_in? {
        if self.type != .inet {
            return nil
        }
        return unsafeCast(of: storage, cast: sockaddr_in.self)
    }
    
    public func inet6() -> sockaddr_in6? {
        if self.type != .inet6 {
            return nil
        }
        return unsafeCast(of: storage, cast: sockaddr_in6.self)
    }
    
    public func unix() -> sockaddr_un? {
        if self.type != .unix {
            return nil
        }
        return unsafeCast(of: storage, cast: sockaddr_un.self)
    }
    
    public var socklen: socklen_t {
        return socklen_t(self.storage.ss_len)
    }
    
    public mutating func addrptr() -> UnsafePointer<sockaddr> {
        return pointer(of: &storage).cast(to: sockaddr.self)
    }
    
    public var port: in_port_t? {
        switch self.type {
        case .inet:
            return unsafeCast(of: self.storage, cast: sockaddr_in.self).sin_port.byteSwapped
        case .inet6:
            return unsafeCast(of: self.storage, cast: sockaddr_in6.self).sin6_port.byteSwapped
        default:
            return nil
        }
    }
    
    public var ip: String? {
        var buffer = [Int8](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        var addr = self.storage
        
        switch self.type {
        case .inet:
            var _in = unsafeCast(of: &addr, cast: sockaddr_in.self).sin_addr
            inet_ntop(AF_INET, &_in, &buffer,
                      UInt32(INET_ADDRSTRLEN))
            
        case .inet6:
            var _in = unsafeCast(of: &addr, cast: sockaddr_in6.self).sin6_addr
            inet_ntop(AF_INET6, &_in, &buffer,
                      UInt32(INET6_ADDRSTRLEN))
        default:
            return nil
        }
        return String(cString: buffer)
    }
    
    public var path: String? {
        if self.type != .unix {
            return nil
        }
        var stor = storage
        var buffer = [Int8](repeating: 0, count: System.maximum.pathname + 1)
        strncpy(&buffer, pointer(of: &stor.__ss_pad1).cast(to: Int8.self), Int(System.maximum.pathname))
        return String(cString: buffer)
    }
}
