//
//  AnnotationConstants.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 10/17/25.
//

enum AnnotationViewConstants {
    enum Texts {
        static let annotationViewTitle = "Annotation View"
        
        static let selectedClassPrefixText = "Selected class: "
        static let finishText = "Finish"
        static let nextText = "Next"
        
        static let selectObjectText = "Select an object"
        static let selectAllLabelText = "Select All"
        
        static let confirmAnnotationFailedTitle = "Cannot confirm annotation"
        static let depthOrSegmentationUnavailableText = "Depth or segmentation related information is not available." +
        "\nDo you want to upload all the objects as a single point with the current location?"
        static let confirmAnnotationFailedConfirmText = "Yes"
        static let confirmAnnotationFailedCancelText = "No"
        
        static let uploadFailedTitle = "Upload Failed"
        static let uploadFailedMessage = "Failed to upload the annotated data. Please try again."
        
        // Upload status messages
        static let discardingAllObjectsMessage = "Discarding all objects"
        static let noObjectsToUploadMessage = "No objects to upload"
        static let workspaceIdNilMessage = "Workspace ID is nil"
        static let apiFailedMessage = "API failed"
        
        static let selectCorrectAnnotationText = "Select correct annotation"
        static let doneText = "Done"
    }
    
    enum Images {
        static let checkIcon = "checkmark"
        static let ellipsisIcon = "ellipsis"
    }
}

enum AnnotationOptionClass: String, CaseIterable {
    case agree = "I agree with this class annotation"
    case missingInstances = "Annotation is missing some instances"
//    case misidentified = "The class annotation is misidentified"
    case discard = "I wish to discard this class annotation"
}

enum AnnotationOptionObject: String, CaseIterable {
    case agree = "I agree with this object annotation"
    case discard = "I wish to discard this object annotation"
}

protocol AnnotationOptionProtocol: RawRepresentable, CaseIterable, Hashable where RawValue == String {}

extension AnnotationOptionClass: AnnotationOptionProtocol {}
extension AnnotationOptionObject: AnnotationOptionProtocol {}

enum AnnotationOption: Hashable {
    case classOption(AnnotationOptionClass)
    case individualOption(AnnotationOptionObject)
    
    var rawValue: String {
        switch self {
        case .classOption(let option): return option.rawValue
        case .individualOption(let option): return option.rawValue
        }
    }
}
