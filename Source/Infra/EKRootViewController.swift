//
//  EntryViewController.swift
//  SwiftEntryKit
//
//  Created by Daniel Huri on 4/19/18.
//  Copyright (c) 2018 huri000@gmail.com. All rights reserved.
//

import UIKit

protocol EntryPresenterDelegate: AnyObject {
    var isResponsiveToTouches: Bool { set get }
    func displayPendingEntryOrRollbackWindow(dismissCompletionHandler: SwiftEntryKit.DismissCompletionHandler?)
}

class EKRootViewController: UIViewController {
    
    // MARK: - Props
    
    private unowned let delegate: EntryPresenterDelegate
    
    private var lastAttributes: EKAttributes!
    // Window setup must expose the incoming orientation before UIKit sees a visible root.
    // Keep this separate from lastAttributes: the latter still owns precedence and exit behavior.
    private var preparedAttributes: EKAttributes?
    private var hostOrientation: UIInterfaceOrientation = .portrait
    private var orientationAttributes: EKAttributes? { preparedAttributes ?? lastAttributes }
    
    private let backgroundView = EKBackgroundView()

    private lazy var wrapperView: EKWrapperView = {
        return EKWrapperView()
    }()
    
    /*
     Count the total amount of currently displaying entries,
     meaning, total subviews less one - the backgorund of the entry
     */
    fileprivate var displayingEntryCount: Int {
        return view.subviews.count - 1
    }
    
    fileprivate var isDisplaying: Bool {
        return lastEntry != nil
    }
    
    private var lastEntry: EKContentView? {
        return view.subviews.last as? EKContentView
    }
        
    private var isResponsive = false {
        didSet {
            wrapperView.isAbleToReceiveTouches = isResponsive
            delegate.isResponsiveToTouches = isResponsive
        }
    }

    override var shouldAutorotate: Bool {
        return orientationAttributes?.positionConstraints.rotation.isEnabled ?? true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        guard let attributes = orientationAttributes else {
            return super.supportedInterfaceOrientations
        }
        switch attributes.positionConstraints.rotation.supportedInterfaceOrientations {
        case .standard:
            return super.supportedInterfaceOrientations
        case .all:
            return .all
        case .specified(let orientation):
            return orientation
        }
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        let supported = supportedInterfaceOrientations
        if supported.contains(mask(for: hostOrientation)) { return hostOrientation }
        for orientation in [UIInterfaceOrientation.portrait, .landscapeLeft, .landscapeRight, .portraitUpsideDown] {
            if supported.contains(mask(for: orientation)) { return orientation }
        }
        return super.preferredInterfaceOrientationForPresentation
    }

    func prepareForPresentation(attributes: EKAttributes, hostOrientation: UIInterfaceOrientation?) {
        preparedAttributes = attributes
        if let orientation = hostOrientation, orientation != .unknown {
            self.hostOrientation = orientation
        }
    }

    private func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return []
        }
    }

    // Previous status bar style
    private let previousStatusBar: EKAttributes.StatusBar
    
    private var statusBar: EKAttributes.StatusBar? = nil {
        didSet {
            if let statusBar = statusBar, ![statusBar, oldValue].contains(.ignored) {
                UIApplication.shared.set(statusBarStyle: statusBar)
            }
        }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if [previousStatusBar, statusBar].contains(.ignored) {
            return super.preferredStatusBarStyle
        }
        return statusBar?.appearance.style ?? previousStatusBar.appearance.style
    }

    override var prefersStatusBarHidden: Bool {
        if [previousStatusBar, statusBar].contains(.ignored) {
            return super.prefersStatusBarHidden
        }
        return !(statusBar?.appearance.visible ?? previousStatusBar.appearance.visible)
    }
    
    // MARK: - Lifecycle
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public init(with delegate: EntryPresenterDelegate) {
        self.delegate = delegate
        previousStatusBar = .currentStatusBar
        super.init(nibName: nil, bundle: nil)
    }
    
    override public func loadView() {
        view = wrapperView
        view.insertSubview(backgroundView, at: 0)
        backgroundView.isUserInteractionEnabled = false
        backgroundView.fillSuperview()
    }
    
    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        statusBar = previousStatusBar
    }
    
    // Set status bar
    func setStatusBarStyle(for attributes: EKAttributes) {
        statusBar = attributes.statusBar
    }
    
    // MARK: - Setup
    
    func configure(entryView: EKEntryView) {

        // In case the entry is a view controller, add the entry as child of root
        if let viewController = entryView.content.viewController {
            addChild(viewController)
        }
        
        // Extract the attributes struct
        let attributes = entryView.attributes
        
        // Assign attributes
        let previousAttributes = lastAttributes
        
        // Remove the last entry
        removeLastEntry(lastAttributes: previousAttributes, keepWindow: true)
        
        lastAttributes = attributes
        preparedAttributes = nil
        
        let entryContentView = EKContentView(withEntryDelegate: self)
        view.addSubview(entryContentView)
        entryContentView.setup(with: entryView)
        
        switch attributes.screenInteraction.defaultAction {
        case .forward:
            isResponsive = false
        default:
            isResponsive = true
        }

        if previousAttributes?.statusBar != attributes.statusBar {
            setNeedsStatusBarAppearanceUpdate()
        }
        
        if shouldAutorotate {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
        
    // Check priority precedence for a given entry
    func canDisplay(attributes: EKAttributes) -> Bool {
        guard let lastAttributes = lastAttributes else {
            return true
        }
        return attributes.precedence.priority >= lastAttributes.precedence.priority
    }

    // Removes last entry - can keep the window 'ON' if necessary
    private func removeLastEntry(lastAttributes: EKAttributes?, keepWindow: Bool) {
        guard let attributes = lastAttributes else {
            return
        }
        if attributes.popBehavior.isOverriden {
            lastEntry?.removePromptly()
        } else {
            popLastEntry()
        }
    }
    
    // Make last entry exit using exitAnimation - animatedly
    func animateOutLastEntry(completionHandler: SwiftEntryKit.DismissCompletionHandler? = nil) {
        lastEntry?.dismissHandler = completionHandler
        lastEntry?.animateOut(pushOut: false)
    }
    
    // Pops last entry (using pop animation) - animatedly
    func popLastEntry() {
        lastEntry?.animateOut(pushOut: true)
    }
}

// MARK: - UIResponder

extension EKRootViewController {
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch lastAttributes.screenInteraction.defaultAction {
        case .dismissEntry:
            lastEntry?.animateOut(pushOut: false)
            fallthrough
        default:
            lastAttributes.screenInteraction.customTapActions.forEach { $0() }
        }
    }
}

// MARK: - EntryScrollViewDelegate

extension EKRootViewController: EntryContentViewDelegate {
    
    func didFinishDisplaying(entry: EKEntryView, keepWindowActive: Bool, dismissCompletionHandler: SwiftEntryKit.DismissCompletionHandler?) {
        guard !isDisplaying else {
            return
        }
        
        guard !keepWindowActive else {
            return
        }
        
        delegate.displayPendingEntryOrRollbackWindow(dismissCompletionHandler: dismissCompletionHandler)
    }
    
    func changeToInactive(withAttributes attributes: EKAttributes, pushOut: Bool) {
        guard displayingEntryCount <= 1 else {
            return
        }
        
        let clear = {
            let style = EKBackgroundView.Style(background: .clear, displayMode: attributes.displayMode)
            self.changeBackground(to: style, duration: attributes.exitAnimation.totalDuration)
        }
        
        guard pushOut else {
            clear()
            return
        }
        
        guard let lastBackroundStyle = lastAttributes?.screenBackground else {
            clear()
            return
        }
        
        if lastBackroundStyle != attributes.screenBackground {
            clear()
        }
    }
    
    func changeToActive(withAttributes attributes: EKAttributes) {
        let style = EKBackgroundView.Style(background: attributes.screenBackground,
                                           displayMode: attributes.displayMode)
        changeBackground(to: style, duration: attributes.entranceAnimation.totalDuration)
    }
    
    private func changeBackground(to style: EKBackgroundView.Style, duration: TimeInterval) {
        DispatchQueue.main.async {
            UIView.animate(withDuration: duration, delay: 0, options: [], animations: {
                self.backgroundView.style = style
            }, completion: nil)
        }
    }
}

