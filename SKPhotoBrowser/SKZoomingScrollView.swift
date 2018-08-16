//
//  SKZoomingScrollView.swift
//  SKViewExample
//
//  Created by suzuki_keihsi on 2015/10/01.
//  Copyright © 2015 suzuki_keishi. All rights reserved.
//

import UIKit
import SceneKit
import CoreMotion
import ImageIO

public protocol CTPanoramaCompass {
    func updateUI(rotationAngle: CGFloat, fieldOfViewAngle: CGFloat)
}

public enum CTPanoramaControlMethod: Int {
    case motion
    case touch
}

public enum CTPanoramaType: Int {
    case cylindrical
    case spherical
}

open class CTPanoramaView: UIView {
    
    // MARK: Public properties
    
    public var panSpeed = CGPoint(x: 0.005, y: 0.005)
    
    public var image: UIImage? {
        didSet {
            panoramaType = panoramaTypeForCurrentImage
        }
    }
    
    public var overlayView: UIView? {
        didSet {
            replace(overlayView: oldValue, with: overlayView)
        }
    }
    
    public var panoramaType: CTPanoramaType = .cylindrical {
        didSet {
            createGeometryNode()
            resetCameraAngles()
        }
    }
    
    public var controlMethod: CTPanoramaControlMethod = .touch {
        didSet {
            switchControlMethod(to: controlMethod)
            resetCameraAngles()
        }
    }
    
    public var compass: CTPanoramaCompass?
    public var movementHandler: ((_ rotationAngle: CGFloat, _ fieldOfViewAngle: CGFloat) -> Void)?
    
    // MARK: Private properties
    
    private let radius: CGFloat = 10
    private let sceneView = SCNView()
    private let scene = SCNScene()
    private let motionManager = CMMotionManager()
    private var geometryNode: SCNNode?
    private var prevLocation = CGPoint.zero
    private var prevBounds = CGRect.zero
    
    private lazy var cameraNode: SCNNode = {
        let node = SCNNode()
        let camera = SCNCamera()
        node.camera = camera
        return node
    }()
    
    private lazy var opQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInteractive
        return queue
    }()
    
    private lazy var fovHeight: CGFloat = {
        return tan(self.yFov/2 * .pi / 180.0) * 2 * self.radius
    }()
    
    private var xFov: CGFloat {
        return yFov * self.bounds.width / self.bounds.height
    }
    
    private var yFov: CGFloat {
        get {
            if #available(iOS 11.0, *) {
                return cameraNode.camera?.fieldOfView ?? 0
            } else {
                return CGFloat(cameraNode.camera?.yFov ?? 0)
            }
        }
        set {
            if #available(iOS 11.0, *) {
                cameraNode.camera?.fieldOfView = newValue
            } else {
                cameraNode.camera?.yFov = Double(newValue)
            }
        }
    }
    
    private var panoramaTypeForCurrentImage: CTPanoramaType {
        if let image = image {
            if image.size.width / image.size.height == 2 {
                return .spherical
            }
        }
        return .cylindrical
    }
    
    // MARK: Class lifecycle methods
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    
    public init(frame: CGRect, fieldOfView: CGFloat) {
        super.init(frame: frame)
        commonInit(fieldOfView)
    }
    
    public convenience init(frame: CGRect, image: UIImage, fieldOfView: CGFloat) {
        self.init(frame: frame, fieldOfView: fieldOfView)
        // Force Swift to call the property observer by calling the setter from a non-init context
        ({ self.image = image })()
    }
    
    deinit {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }
    
    private func commonInit(_ fieldOfView: CGFloat = 70) {
        add(view: sceneView)
        
        self.backgroundColor = UIColor.black
        
        scene.rootNode.addChildNode(cameraNode)
        scene.background.contents = UIColor.clear
        
        yFov = fieldOfView
        
        sceneView.scene = scene
        sceneView.backgroundColor = UIColor.black
        
        switchControlMethod(to: controlMethod)
        
        resetCameraAngles()
        
        sceneView.prepare([scene], completionHandler: nil)
    }
    
    // MARK: Configuration helper methods
    
    private func createGeometryNode() {
        
        guard let image = image else {return}

        geometryNode?.removeFromParentNode()
        
        let material = SCNMaterial()
        
        material.diffuse.contents = image
        material.diffuse.mipFilter = .nearest
        material.diffuse.magnificationFilter = .nearest
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(-1, 1, 1)
        material.diffuse.wrapS = .repeat
        
        material.cullMode = .front
        
        if panoramaType == .spherical {
            let sphere = SCNSphere(radius: radius)
            sphere.segmentCount = 300
            sphere.firstMaterial = material
            
            let sphereNode = SCNNode()
            sphereNode.geometry = sphere
            geometryNode = sphereNode
        } else {
            let tube = SCNTube(innerRadius: radius, outerRadius: radius, height: fovHeight)
            tube.heightSegmentCount = 50
            tube.radialSegmentCount = 300
            tube.firstMaterial = material
            
            let tubeNode = SCNNode()
            tubeNode.geometry = tube
            geometryNode = tubeNode
        }
        scene.rootNode.addChildNode(geometryNode!)
    }
    
    private func replace(overlayView: UIView?, with newOverlayView: UIView?) {
        overlayView?.removeFromSuperview()
        guard let newOverlayView = newOverlayView else {return}
        add(view: newOverlayView)
    }
    
    private func switchControlMethod(to method: CTPanoramaControlMethod) {
        sceneView.gestureRecognizers?.removeAll()
        
        if method == .touch {
            let panGestureRec = UIPanGestureRecognizer(target: self, action: #selector(handlePan(panRec:)))
            sceneView.addGestureRecognizer(panGestureRec)
            sceneView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(panRec:))))
            
            if motionManager.isDeviceMotionActive {
                motionManager.stopDeviceMotionUpdates()
            }
        } else {
            guard motionManager.isDeviceMotionAvailable else {return}
            motionManager.deviceMotionUpdateInterval = 0.015
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: opQueue,
                                                   withHandler: { [weak self] (motionData, error) in
                                                    guard let panoramaView = self else {return}
                                                    guard panoramaView.controlMethod == .motion else {return}
                                                    
                                                    guard let motionData = motionData else {
                                                        print("\(String(describing: error?.localizedDescription))")
                                                        panoramaView.motionManager.stopDeviceMotionUpdates()
                                                        return
                                                    }
                                                    
                                                    let rotationMatrix = motionData.attitude.rotationMatrix
                                                    var userHeading = .pi - atan2(rotationMatrix.m32, rotationMatrix.m31)
                                                    userHeading += .pi/2
                                                    
                                                    DispatchQueue.main.async {
                                                        if panoramaView.panoramaType == .cylindrical {
                                                            // Prevent vertical movement in a cylindrical panorama
                                                            panoramaView.cameraNode.eulerAngles = SCNVector3Make(0, Float(-userHeading), 0)
                                                        } else {
                                                            // Use quaternions when in spherical mode to prevent gimbal lock
                                                            panoramaView.cameraNode.orientation = motionData.orientation()
                                                        }
                                                        panoramaView.reportMovement(CGFloat(userHeading), panoramaView.xFov.toRadians())
                                                    }
            })
        }
    }
    
    private func resetCameraAngles() {
        cameraNode.eulerAngles = SCNVector3Make(0, Float(Double.pi), 0)
        self.reportMovement(0, xFov.toRadians(), callHandler: false)
    }
    
    private func reportMovement(_ rotationAngle: CGFloat, _ fieldOfViewAngle: CGFloat, callHandler: Bool = true) {
        compass?.updateUI(rotationAngle: rotationAngle, fieldOfViewAngle: fieldOfViewAngle)
        if callHandler {
            movementHandler?(rotationAngle, fieldOfViewAngle)
        }
    }
    
    // MARK: Gesture handling
    
    var lastScale: CGFloat = 0

    @objc private func handlePinch(panRec: UIPinchGestureRecognizer) {
        
        if panRec.state == .began {
            lastScale = panRec.scale
        } else if panRec.state == .changed {
            let ds = lastScale - panRec.scale
            yFov = yFov + ds * 20
            lastScale = panRec.scale
        }
        
        yFov = min(max(yFov, 70), 125)
    }
    
    @objc private func handlePan(panRec: UIPanGestureRecognizer) {
        if panRec.state == .began {
            prevLocation = CGPoint.zero
        } else if panRec.state == .changed {
            var modifiedPanSpeed = panSpeed
            
            if panoramaType == .cylindrical {
                modifiedPanSpeed.y = 0 // Prevent vertical movement in a cylindrical panorama
            }
            
            let location = panRec.translation(in: sceneView)
            let orientation = cameraNode.eulerAngles
            var newOrientation = SCNVector3Make(orientation.x + Float(location.y - prevLocation.y) * Float(modifiedPanSpeed.y),
                                                orientation.y + Float(location.x - prevLocation.x) * Float(modifiedPanSpeed.x),
                                                orientation.z)
            
            if controlMethod == .touch {
                newOrientation.x = max(min(newOrientation.x, 1.1), -1.1)
            }
            
            cameraNode.eulerAngles = newOrientation
            prevLocation = location
            
            reportMovement(CGFloat(-cameraNode.eulerAngles.y), xFov.toRadians())
        }
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size.width != prevBounds.size.width || bounds.size.height != prevBounds.size.height {
            sceneView.setNeedsDisplay()
            reportMovement(CGFloat(-cameraNode.eulerAngles.y), xFov.toRadians(), callHandler: false)
        }
    }
}

fileprivate extension CMDeviceMotion {
    
    func orientation() -> SCNVector4 {
        
        let attitude = self.attitude.quaternion
        let attitudeQuanternion = GLKQuaternion(quanternion: attitude)
        
        let result: SCNVector4
        
        switch UIApplication.shared.statusBarOrientation {
            
        case .landscapeRight:
            let cq1 = GLKQuaternionMakeWithAngleAndAxis(.pi/2, 0, 1, 0)
            let cq2 = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 1, 0, 0)
            var quanternionMultiplier = GLKQuaternionMultiply(cq1, attitudeQuanternion)
            quanternionMultiplier = GLKQuaternionMultiply(cq2, quanternionMultiplier)
            
            result = quanternionMultiplier.vector(for: .landscapeRight)
            
        case .landscapeLeft:
            let cq1 = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 0, 1, 0)
            let cq2 = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 1, 0, 0)
            var quanternionMultiplier = GLKQuaternionMultiply(cq1, attitudeQuanternion)
            quanternionMultiplier = GLKQuaternionMultiply(cq2, quanternionMultiplier)
            
            result = quanternionMultiplier.vector(for: .landscapeLeft)
            
        case .portraitUpsideDown:
            let cq1 = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 1, 0, 0)
            let cq2 = GLKQuaternionMakeWithAngleAndAxis(.pi, 0, 0, 1)
            var quanternionMultiplier = GLKQuaternionMultiply(cq1, attitudeQuanternion)
            quanternionMultiplier = GLKQuaternionMultiply(cq2, quanternionMultiplier)
            
            result = quanternionMultiplier.vector(for: .portraitUpsideDown)
            
        case .unknown, .portrait:
            let clockwiseQuanternion = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 1, 0, 0)
            let quanternionMultiplier = GLKQuaternionMultiply(clockwiseQuanternion, attitudeQuanternion)
            
            result = quanternionMultiplier.vector(for: .portrait)
        }
        return result
    }
}

fileprivate extension UIView {
    func add(view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        let views = ["view": view]
        let hConstraints = NSLayoutConstraint.constraints(withVisualFormat: "|[view]|", options: [], metrics: nil, views: views)    //swiftlint:disable:this line_length
        let vConstraints = NSLayoutConstraint.constraints(withVisualFormat: "V:|[view]|", options: [], metrics: nil, views: views)  //swiftlint:disable:this line_length
        self.addConstraints(hConstraints)
        self.addConstraints(vConstraints)
    }
}

fileprivate extension FloatingPoint {
    func toDegrees() -> Self {
        return self * 180 / .pi
    }
    
    func toRadians() -> Self {
        return self * .pi / 180
    }
}

private extension GLKQuaternion {
    init(quanternion: CMQuaternion) {
        self.init(q: (Float(quanternion.x), Float(quanternion.y), Float(quanternion.z), Float(quanternion.w)))
    }
    
    func vector(for orientation: UIInterfaceOrientation) -> SCNVector4 {
        switch orientation {
        case .landscapeRight:
            return SCNVector4(x: -self.y, y: self.x, z: self.z, w: self.w)
            
        case .landscapeLeft:
            return SCNVector4(x: self.y, y: -self.x, z: self.z, w: self.w)
            
        case .portraitUpsideDown:
            return SCNVector4(x: -self.x, y: -self.y, z: self.z, w: self.w)
            
        case .unknown, .portrait:
            return SCNVector4(x: self.x, y: self.y, z: self.z, w: self.w)
        }
    }
}

open class SKZoomingScrollView: UIScrollView {
    var captionView: SKCaptionView!
    var photo: SKPhotoProtocol! {
        didSet {
            if let imageView = photoImageView as? UIImageView {
                imageView.image = nil
            }
            if let panoramaView = photoImageView as? CTPanoramaView {
                panoramaView.image = nil
            }
            if photo != nil {
                setupImageView()
                displayImage(complete: false)
            }
        }
    }
    
    fileprivate(set) var photoImageView: UIView!
    fileprivate weak var photoBrowser: SKPhotoBrowser?
    fileprivate var tapView: SKDetectingView!
    fileprivate var indicatorView: SKIndicatorView!
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    convenience init(frame: CGRect, browser: SKPhotoBrowser) {
        self.init(frame: frame)
        photoBrowser = browser
        setup()
    }
    
    deinit {
        photoBrowser = nil
    }
    
    func setup() {
        // tap
        tapView = SKDetectingView(frame: bounds)
        tapView.delegate = self
        tapView.backgroundColor = UIColor.clear
        tapView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        addSubview(tapView)

        // indicator
        indicatorView = SKIndicatorView(frame: frame)
        addSubview(indicatorView)
        
        // self
        backgroundColor = UIColor.black
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        decelerationRate = UIScrollViewDecelerationRateFast
        autoresizingMask = [.flexibleWidth, .flexibleTopMargin, .flexibleBottomMargin, .flexibleRightMargin, .flexibleLeftMargin]
    }
    
    func setupImageView() {
        if photo.is360 {
            if photoImageView is CTPanoramaView {
                return
            }
            photoImageView?.removeFromSuperview()
            photoImageView = CTPanoramaView(frame: self.bounds, fieldOfView: SKPhotoBrowserOptions.yFov)
            photoImageView.contentMode = .bottom
            photoImageView.backgroundColor = UIColor.black
            insertSubview(photoImageView, belowSubview: indicatorView)
        } else {
            if photoImageView is SKDetectingImageView {
                return
            }
            photoImageView?.removeFromSuperview()
            let detectingImageView = SKDetectingImageView(frame: .zero)
            detectingImageView.delegate = self
            photoImageView = detectingImageView
            photoImageView.contentMode = .bottom
            photoImageView.backgroundColor = UIColor.black
            insertSubview(photoImageView, belowSubview: indicatorView)
        }
    }
    
    // MARK: - override
    
    open override func layoutSubviews() {
        tapView.frame = bounds
        indicatorView.frame = bounds
        
        super.layoutSubviews()
        
        let boundsSize = bounds.size
        
        if photo.is360 {
            if !photoImageView.frame.equalTo(bounds) {
                photoImageView.frame = CGRect(x: 0, y: 0, width: bounds.size.width, height: bounds.size.height)
            }
            return
        }
        
        var frameToCenter = photoImageView.frame
        
        // horizon
        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = floor((boundsSize.width - frameToCenter.size.width) / 2)
        } else {
            frameToCenter.origin.x = 0
        }
        // vertical
        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = floor((boundsSize.height - frameToCenter.size.height) / 2)
        } else {
            frameToCenter.origin.y = 0
        }
        
        // Center
        if !photoImageView.frame.equalTo(frameToCenter) {
            photoImageView.frame = frameToCenter
        }
    }
    
    func imageViewHasImageSet() -> Bool {
        if let panoramaView = photoImageView as? CTPanoramaView {
            return panoramaView.image != nil
        }
        if let imageView = photoImageView as? UIImageView {
            return imageView.image != nil
        }
        return false
    }
    
    open func setMaxMinZoomScalesForCurrentBounds() {
        
        if photo.is360 {
            return
        }
        
        maximumZoomScale = 1
        minimumZoomScale = 1
        
        if imageViewHasImageSet() {
            zoomScale = 1
        }
        
        guard let photoImageView = photoImageView else {
            return
        }
        
        let boundsSize = bounds.size
        let imageSize = photoImageView.frame.size
        
        let xScale = boundsSize.width / imageSize.width
        let yScale = boundsSize.height / imageSize.height
        let minScale: CGFloat = min(xScale, yScale)
        var maxScale: CGFloat = 1.0
        
        let scale = max(UIScreen.main.scale, 2.0)
        let deviceScreenWidth = UIScreen.main.bounds.width * scale // width in pixels. scale needs to remove if to use the old algorithm
        let deviceScreenHeight = UIScreen.main.bounds.height * scale // height in pixels. scale needs to remove if to use the old algorithm
        
        if photoImageView.frame.width < deviceScreenWidth {
            // I think that we should to get coefficient between device screen width and image width and assign it to maxScale. I made two mode that we will get the same result for different device orientations.
            if UIApplication.shared.statusBarOrientation.isPortrait {
                maxScale = deviceScreenHeight / photoImageView.frame.width
            } else {
                maxScale = deviceScreenWidth / photoImageView.frame.width
            }
        } else if photoImageView.frame.width > deviceScreenWidth {
            maxScale = 1.0
        } else {
            // here if photoImageView.frame.width == deviceScreenWidth
            maxScale = 2.5
        }
    
        photoImageView.frame = CGRect(x: 0, y: 0, width: photoImageView.frame.size.width, height: photoImageView.frame.size.height)
        
        maximumZoomScale = maxScale
        minimumZoomScale = minScale
        
        if imageViewHasImageSet() {
            zoomScale = minScale
        }
        
        // on high resolution screens we have double the pixel density, so we will be seeing every pixel if we limit the
        // maximum zoom scale to 0.5
        // After changing this value, we still never use more
        /*
        maxScale = maxScale / scale 
        if maxScale < minScale {
            maxScale = minScale * 2
        }
        */
        
        // reset position
        
        setNeedsLayout()
    }
    
    open func prepareForReuse() {
        photo = nil
        if captionView != nil {
            captionView.removeFromSuperview()
            captionView = nil 
        }
    }
    
    // MARK: - image
    open func displayImage(complete flag: Bool) {
        // reset scale
        maximumZoomScale = 1
        minimumZoomScale = 1
        zoomScale = 1
        contentSize = CGSize.zero
        
        if !flag {
            if photo.underlyingImage == nil {
                indicatorView.startAnimating()
            }
            photo.loadUnderlyingImageAndNotify()
        } else {
            indicatorView.stopAnimating()
        }
        
        if let image = photo.underlyingImage {
            
            // performance slowed #145
 
            // create padding
            // let width: CGFloat = image.size.width + SKPhotoBrowserOptions.imagePaddingX
            // let height: CGFloat = image.size.height + SKPhotoBrowserOptions.imagePaddingY;
            // UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), false, 0.0);
            // let context: CGContextRef = UIGraphicsGetCurrentContext()!;
            // UIGraphicsPushContext(context);
            // let origin: CGPoint = CGPointMake((width - image.size.width) / 2, (height - image.size.height) / 2);
            // image.drawAtPoint(origin)
            // UIGraphicsPopContext();
            // let imageWithPadding = UIGraphicsGetImageFromCurrentImageContext();
            // UIGraphicsEndImageContext();

            // image
            if let imageView = photoImageView as? UIImageView {
                imageView.image = image
            }
            if let panoramaView = photoImageView as? CTPanoramaView {
                panoramaView.image = image
            }
            photoImageView.contentMode = photo.contentMode
            photoImageView.backgroundColor = SKPhotoBrowserOptions.backgroundColor
            
            var photoImageViewFrame = CGRect.zero
            photoImageViewFrame.origin = CGPoint.zero
            photoImageViewFrame.size = image.size
            
            photoImageView.frame = photoImageViewFrame
            
            if let panoramaView = photoImageView as? CTPanoramaView {
                contentSize = self.frame.size
                maximumZoomScale = 1
                minimumZoomScale = 1
                zoomScale = 1
            }
            if let imageView = photoImageView as? UIImageView {
                contentSize = photoImageViewFrame.size
                setMaxMinZoomScalesForCurrentBounds()
            }
        }
        setNeedsLayout()
    }
    
    open func displayImageFailure() {
        indicatorView.stopAnimating()
    }
    
    // MARK: - handle tap
    open func handleDoubleTap(_ touchPoint: CGPoint) {
        if let photoBrowser = photoBrowser {
            NSObject.cancelPreviousPerformRequests(withTarget: photoBrowser)
        }
        
        if zoomScale > minimumZoomScale {
            // zoom out
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            // zoom in
            // I think that the result should be the same after double touch or pinch
           /* var newZoom: CGFloat = zoomScale * 3.13
            if newZoom >= maximumZoomScale {
                newZoom = maximumZoomScale
            }
            */
            let zoomRect = zoomRectForScrollViewWith(maximumZoomScale, touchPoint: touchPoint)
            zoom(to: zoomRect, animated: true)
        }
        
        // delay control
        photoBrowser?.hideControlsAfterDelay()
    }
}

// MARK: - UIScrollViewDelegate

extension SKZoomingScrollView: UIScrollViewDelegate {
    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return photoImageView
    }
    
    public func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        scrollView.pinchGestureRecognizer?.isEnabled = !photo.is360
        photoBrowser?.cancelControlHiding()
    }
    
    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        setNeedsLayout()
        layoutIfNeeded()
    }
}

// MARK: - SKDetectingImageViewDelegate

extension SKZoomingScrollView: SKDetectingViewDelegate {
    func handleSingleTap(_ view: UIView, touch: UITouch) {
        guard let browser = photoBrowser else {
            return
        }
        guard SKPhotoBrowserOptions.enableZoomBlackArea == true else {
            return
        }
        
        if browser.areControlsHidden() == false && SKPhotoBrowserOptions.enableSingleTapDismiss == true {
            browser.determineAndClose()
        } else {
            browser.toggleControls()
        }
    }
    
    func handleDoubleTap(_ view: UIView, touch: UITouch) {
        if SKPhotoBrowserOptions.enableZoomBlackArea == true {
            let needPoint = getViewFramePercent(view, touch: touch)
            handleDoubleTap(needPoint)
        }
    }
}


// MARK: - SKDetectingImageViewDelegate

extension SKZoomingScrollView: SKDetectingImageViewDelegate {
    func handleImageViewSingleTap(_ touchPoint: CGPoint) {
        guard let browser = photoBrowser else {
            return
        }
        if SKPhotoBrowserOptions.enableSingleTapDismiss {
            browser.determineAndClose()
        } else {
            browser.toggleControls()
        }
    }
    
    func handleImageViewDoubleTap(_ touchPoint: CGPoint) {
        handleDoubleTap(touchPoint)
    }
}

private extension SKZoomingScrollView {
    func getViewFramePercent(_ view: UIView, touch: UITouch) -> CGPoint {
        let oneWidthViewPercent = view.bounds.width / 100
        let viewTouchPoint = touch.location(in: view)
        let viewWidthTouch = viewTouchPoint.x
        let viewPercentTouch = viewWidthTouch / oneWidthViewPercent
        
        let photoWidth = photoImageView.bounds.width
        let onePhotoPercent = photoWidth / 100
        let needPoint = viewPercentTouch * onePhotoPercent
        
        var Y: CGFloat!
        
        if viewTouchPoint.y < view.bounds.height / 2 {
            Y = 0
        } else {
            Y = photoImageView.bounds.height
        }
        let allPoint = CGPoint(x: needPoint, y: Y)
        return allPoint
    }
    
    func zoomRectForScrollViewWith(_ scale: CGFloat, touchPoint: CGPoint) -> CGRect {
        let w = frame.size.width / scale
        let h = frame.size.height / scale
        let x = touchPoint.x - (h / max(UIScreen.main.scale, 2.0))
        let y = touchPoint.y - (w / max(UIScreen.main.scale, 2.0))
        
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
