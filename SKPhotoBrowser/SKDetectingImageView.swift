//
//  SKDetectingImageView.swift
//  SKPhotoBrowser
//
//  Created by suzuki_keishi on 2015/10/01.
//  Copyright © 2015 suzuki_keishi. All rights reserved.
//

import UIKit

@objc protocol SKDetectingImageViewDelegate {
    func handleImageViewSingleTap(_ touchPoint: CGPoint)
    func handleImageViewDoubleTap(_ touchPoint: CGPoint)
}

class SKDetectingImageView: UIImageView {
    
    weak var delegate: SKDetectingImageViewDelegate?
    
    var imageView: UIImageView?
    var labelView: UILabel?
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    func setup() {
        
        isUserInteractionEnabled = true
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
        
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 150, height: 150))
        imageView.isHidden = true
        imageView.contentMode = .scaleAspectFit
        imageView.image = image
        addSubview(imageView)
        self.imageView = imageView
        
        let label = UILabel(frame: .zero)
        label.isHidden = true
        label.font = UIFont.boldSystemFont(ofSize: 70)
        label.textColor = .white
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowRadius = 3
        label.layer.shadowOffset = .zero
        label.layer.shadowOpacity = 0.5
        label.layer.masksToBounds = false
        addSubview(label)
        self.labelView = label
    }
    
    func addIconOverlayer(_ image: UIImage?) {
        labelView?.isHidden = true
        imageView?.isHidden = false
        imageView?.image = image
        setNeedsLayout()
        setNeedsDisplay()
    }
    
    func addDownloadProgress(_ progress: Int) {
        labelView?.isHidden = false
        imageView?.isHidden = true
        labelView?.text = "\(progress)%"
        setNeedsLayout()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for item in subviews {
            if let imageview = item as? UIImageView {
                imageview.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            }
            if let label = item as? UILabel {
                label.sizeToFit()
                label.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            }
        }
    }
    
    @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        delegate?.handleImageViewDoubleTap(recognizer.location(in: self))
    }
    
    @objc func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        delegate?.handleImageViewSingleTap(recognizer.location(in: self))
    }
}
