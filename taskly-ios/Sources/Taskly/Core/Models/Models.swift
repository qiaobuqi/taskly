import Foundation

// MARK: - User

struct User: Codable, Identifiable, Hashable {
    let id: Int
    var nickname: String
    var avatar: String?
    var bio: String?
    var skillTags: [String]
    var rating: Double
    var completedCount: Int
    var isVerified: Bool
    var verificationStatus: VerificationStatus
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, nickname, avatar, bio, rating
        case skillTags = "skill_tags"
        case completedCount = "completed_count"
        case isVerified = "is_verified"
        case verificationStatus = "verification_status"
        case createdAt = "created_at"
    }

    static func == (lhs: User, rhs: User) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum VerificationStatus: String, Codable {
    case none = "none"
    case pending = "pending"
    case approved = "approved"
    case rejected = "rejected"
}

// MARK: - Task

struct TaskItem: Codable, Identifiable, Hashable {
    let id: Int
    var title: String
    var description: String
    var category: TaskCategory
    var budget: Double
    var currency: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var deadline: Date?
    var status: TaskStatus
    var publisherId: Int
    var publisher: User?
    var assigneeId: Int?
    var assignee: User?
    var images: [String]
    var applicantCount: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, budget, currency
        case address, latitude, longitude, deadline, status, images
        case publisherId = "publisher_id"
        case publisher
        case assigneeId = "assignee_id"
        case assignee
        case applicantCount = "applicant_count"
        case createdAt = "created_at"
    }

    static func == (lhs: TaskItem, rhs: TaskItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum TaskCategory: String, Codable, CaseIterable {
    case repair = "repair"
    case moving = "moving"
    case errand = "errand"
    case it = "it"
    case other = "other"

    var displayName: String {
        switch self {
        case .repair: return "Repair"
        case .moving: return "Moving"
        case .errand: return "Errand"
        case .it: return "IT & Tech"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .repair: return "wrench.and.screwdriver"
        case .moving: return "box.truck"
        case .errand: return "figure.walk"
        case .it: return "desktopcomputer"
        case .other: return "ellipsis.circle"
        }
    }
}

enum TaskStatus: String, Codable {
    case open = "open"
    case inProgress = "in_progress"
    case pendingConfirm = "pending_confirm"
    case completed = "completed"
    case cancelled = "cancelled"
    case disputed = "disputed"

    var displayName: String {
        switch self {
        case .open: return "Open"
        case .inProgress: return "In Progress"
        case .pendingConfirm: return "Awaiting Confirmation"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .disputed: return "Disputed"
        }
    }

    var color: String {
        switch self {
        case .open: return "green"
        case .inProgress: return "orange"
        case .pendingConfirm: return "blue"
        case .completed: return "gray"
        case .cancelled: return "red"
        case .disputed: return "purple"
        }
    }
}

// MARK: - ServiceCard

struct ServiceCard: Codable, Identifiable, Hashable {
    let id: Int
    var title: String
    var description: String
    var category: TaskCategory
    var minPrice: Double
    var maxPrice: Double
    var currency: String
    var serviceArea: String
    var skillTags: [String]
    var images: [String]
    var providerId: Int
    var provider: User?
    var isActive: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, currency, images
        case minPrice = "min_price"
        case maxPrice = "max_price"
        case serviceArea = "service_area"
        case skillTags = "skill_tags"
        case providerId = "provider_id"
        case provider
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    static func == (lhs: ServiceCard, rhs: ServiceCard) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Application (抢单/报价)

struct Application: Codable, Identifiable {
    let id: Int
    let taskId: Int
    let applicantId: Int
    var applicant: User?
    var message: String
    var proposedPrice: Double
    var status: ApplicationStatus
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, message, status
        case taskId = "task_id"
        case applicantId = "applicant_id"
        case applicant
        case proposedPrice = "proposed_price"
        case createdAt = "created_at"
    }
}

enum ApplicationStatus: String, Codable {
    case pending = "pending"
    case accepted = "accepted"
    case rejected = "rejected"
}

// MARK: - Payment

struct Payment: Codable, Identifiable {
    let id: Int
    let taskId: Int
    let payerId: Int
    let payeeId: Int
    var amount: Double
    var currency: String
    var status: PaymentStatus
    var stripePaymentIntentId: String?
    var commission: Double
    var createdAt: Date
    var releasedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, amount, currency, status, commission
        case taskId = "task_id"
        case payerId = "payer_id"
        case payeeId = "payee_id"
        case stripePaymentIntentId = "stripe_payment_intent_id"
        case createdAt = "created_at"
        case releasedAt = "released_at"
    }
}

enum PaymentStatus: String, Codable {
    case pending = "pending"
    case escrowed = "escrowed"      // 托管中
    case released = "released"      // 已放款
    case refunded = "refunded"      // 已退款
    case disputed = "disputed"      // 争议中
}

// MARK: - Wallet

struct Wallet: Codable {
    var balance: Double
    var escrowedAmount: Double
    var currency: String
    var transactions: [WalletTransaction]

    enum CodingKeys: String, CodingKey {
        case balance, currency, transactions
        case escrowedAmount = "escrowed_amount"
    }
}

struct WalletTransaction: Codable, Identifiable {
    let id: Int
    var type: TransactionType
    var amount: Double
    var currency: String
    var description: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type, amount, currency, description
        case createdAt = "created_at"
    }
}

enum TransactionType: String, Codable {
    case payment = "payment"
    case release = "release"
    case refund = "refund"
    case withdrawal = "withdrawal"
}

// MARK: - Review

struct Review: Codable, Identifiable {
    let id: Int
    let taskId: Int
    let reviewerId: Int
    let revieweeId: Int
    var reviewer: User?
    var rating: Int
    var comment: String
    var images: [String]
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, rating, comment, images, reviewer
        case taskId = "task_id"
        case reviewerId = "reviewer_id"
        case revieweeId = "reviewee_id"
        case createdAt = "created_at"
    }
}

// MARK: - Message

struct ChatMessage: Codable, Identifiable, Equatable {
    let id: Int
    let senderId: Int
    let receiverId: Int
    let taskId: Int?
    var content: String
    var imageUrl: String?
    var isRead: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, content
        case senderId = "sender_id"
        case receiverId = "receiver_id"
        case taskId = "task_id"
        case imageUrl = "image_url"
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}

struct Conversation: Codable, Identifiable {
    let id: Int
    let otherUser: User
    var lastMessage: ChatMessage?
    var unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case otherUser = "other_user"
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        otherUser = try c.decode(User.self, forKey: .otherUser)
        lastMessage = try c.decodeIfPresent(ChatMessage.self, forKey: .lastMessage)
        unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        // The conversation is identified by the person you're talking to.
        id = otherUser.id
    }
}

// MARK: - Verification

struct Verification: Codable {
    var status: VerificationStatus
    var realName: String?
    var documentType: String?
    var submittedAt: Date?
    var reviewedAt: Date?
    var rejectionReason: String?

    enum CodingKeys: String, CodingKey {
        case status
        case realName = "real_name"
        case documentType = "document_type"
        case submittedAt = "submitted_at"
        case reviewedAt = "reviewed_at"
        case rejectionReason = "rejection_reason"
    }
}

// MARK: - API Response

struct APIResponse<T: Codable>: Codable {
    let code: Int
    let message: String
    let data: T?
}

struct PageResponse<T: Codable>: Codable {
    let list: [T]
    let total: Int
    let page: Int
    let pageSize: Int

    enum CodingKeys: String, CodingKey {
        case list, total, page
        case pageSize = "page_size"
    }
}

struct EmptyResponse: Codable {}
