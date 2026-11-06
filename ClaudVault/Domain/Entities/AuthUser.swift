import Foundation

struct AuthUser:Identifiable,Equatable{
    let id:UUID
    let email:String
    let displayName:String?
    let emailVerified:Bool
}
