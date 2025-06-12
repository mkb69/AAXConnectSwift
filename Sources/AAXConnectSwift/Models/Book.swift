import Foundation

public struct CustomerRights: Codable, Sendable {
    public let isConsumable: Bool?
    public let isConsumableIndefinitely: Bool?
    public let isConsumableOffline: Bool?
    public let isConsumableUntil: String? // Assuming 'null' maps to nil String, or a date string

    enum CodingKeys: String, CodingKey {
        case isConsumable = "is_consumable"
        case isConsumableIndefinitely = "is_consumable_indefinitely"
        case isConsumableOffline = "is_consumable_offline"
        case isConsumableUntil = "is_consumable_until"
    }
}

// Book is now a simple data structure, not conforming to Codable directly.
// Sendable conformance is implicit if all members are Sendable (Data is Sendable).
public struct Book: Codable, Sendable {
    public let skuLite: String
    public let asin: String?
    public let sku: String?
    public let title: String
    public let subtitle: String?
    public let authors: [String]?
    public let narrators: [String]?
    public let contributors: Data? // Raw contributors data as JSON Data
    public let releaseDate: String?
    public let purchaseDate: String?
    public let issueDate: String? // Often same as purchase_date
    public let publicationDatetime: String? // More precise than release_date
    public let dateAddedToLibrary: String? // From library_status.date_added
    public let merchandisingSummary: String?
    public let publisherName: String?
    public let language: String?
    public let seriesList: Data? // Raw series data as JSON Data
    public let primarySeriesTitle: String? // Title of the first series entry
    public let runtimeLengthMin: Int?
    public let formatType: String?
    public let contentType: String?
    public let contentDeliveryType: String?
    public let status: String? // e.g., "Active", "Revoked"
    public let isListenable: Bool?
    public let isAdultProduct: Bool?
    public let isPlayable: Bool?
    public let isVisible: Bool?
    public let isFinished: Bool?
    public let isDownloaded: Bool?
    public let percentComplete: Int?
    public let imageUrl: String? // Cover art
    public let sampleUrl: String?
    public let pdfUrl: String?
    public let productImages: [String: String]? // Various image sizes
    public let isbn: String? // ISBN-13

    // Fields from extended response groups
    public let customerRights: CustomerRights?
    public let categories: Data?   // From categories as JSON Data
    public let productExtendedAttrs: Data? // From product_extended_attrs as JSON Data
    public let contentRating: Data? // From product_details.content_rating as JSON Data

    enum CodingKeys: String, CodingKey {
        case skuLite = "sku_lite"
        case asin, sku, title, subtitle, authors, narrators, contributors
        case releaseDate = "release_date"
        case purchaseDate = "purchase_date"
        case issueDate = "issue_date"
        case publicationDatetime = "publication_datetime"
        case dateAddedToLibrary = "date_added_to_library" 
        case merchandisingSummary = "merchandising_summary"
        case publisherName = "publisher_name"
        case language
        case seriesList = "series" 
        case primarySeriesTitle = "primary_series_title"
        case runtimeLengthMin = "runtime_length_min"
        case formatType = "format_type"
        case contentType = "content_type"
        case contentDeliveryType = "content_delivery_type"
        case status
        case isListenable = "is_listenable"
        case isAdultProduct = "is_adult_product"
        case isPlayable = "is_playable"
        case isVisible = "is_visible"
        case isFinished = "is_finished"
        case isDownloaded = "is_downloaded"
        case percentComplete = "percent_complete"
        case imageUrl = "image_url"
        case sampleUrl = "sample_url"
        case pdfUrl = "pdf_url"
        case productImages = "product_images"
        case isbn
        case customerRights = "customer_rights"
        case categories
        case productExtendedAttrs = "product_extended_attrs"
        case contentRating = "content_rating"
    }
    
    // If default Codable doesn't work due to other Data? fields, we'll need custom encode/decode.
    // For now, relying on default implementation.

    public init(
        skuLite: String,
        asin: String? = nil,
        sku: String? = nil,
        title: String,
        subtitle: String? = nil,
        authors: [String]? = nil,
        narrators: [String]? = nil,
        contributors: Data? = nil,
        releaseDate: String? = nil,
        purchaseDate: String? = nil,
        issueDate: String? = nil,
        publicationDatetime: String? = nil,
        dateAddedToLibrary: String? = nil,
        merchandisingSummary: String? = nil,
        publisherName: String? = nil,
        language: String? = nil,
        seriesList: Data? = nil,
        primarySeriesTitle: String? = nil,
        runtimeLengthMin: Int? = nil,
        formatType: String? = nil,
        contentType: String? = nil,
        contentDeliveryType: String? = nil,
        status: String? = nil,
        isListenable: Bool? = nil,
        isAdultProduct: Bool? = nil,
        isPlayable: Bool? = nil,
        isVisible: Bool? = nil,
        isFinished: Bool? = nil,
        isDownloaded: Bool? = nil,
        percentComplete: Int? = nil,
        imageUrl: String? = nil,
        sampleUrl: String? = nil,
        pdfUrl: String? = nil,
        productImages: [String: String]? = nil,
        isbn: String? = nil,
        customerRights: CustomerRights? = nil,
        categories: Data? = nil,
        productExtendedAttrs: Data? = nil,
        contentRating: Data? = nil
    ) {
        self.skuLite = skuLite
        self.asin = asin
        self.sku = sku
        self.title = title
        self.subtitle = subtitle
        self.authors = authors
        self.narrators = narrators
        self.contributors = contributors
        self.releaseDate = releaseDate
        self.purchaseDate = purchaseDate
        self.issueDate = issueDate
        self.publicationDatetime = publicationDatetime
        self.dateAddedToLibrary = dateAddedToLibrary
        self.merchandisingSummary = merchandisingSummary
        self.publisherName = publisherName
        self.language = language
        self.seriesList = seriesList
        self.primarySeriesTitle = primarySeriesTitle
        self.runtimeLengthMin = runtimeLengthMin
        self.formatType = formatType
        self.contentType = contentType
        self.contentDeliveryType = contentDeliveryType
        self.status = status
        self.isListenable = isListenable
        self.isAdultProduct = isAdultProduct
        self.isPlayable = isPlayable
        self.isVisible = isVisible
        self.isFinished = isFinished
        self.isDownloaded = isDownloaded
        self.percentComplete = percentComplete
        self.imageUrl = imageUrl
        self.sampleUrl = sampleUrl
        self.pdfUrl = pdfUrl
        self.productImages = productImages
        self.isbn = isbn
        self.customerRights = customerRights
        self.categories = categories
        self.productExtendedAttrs = productExtendedAttrs
        self.contentRating = contentRating
    }
} 