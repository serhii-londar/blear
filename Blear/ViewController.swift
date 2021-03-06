import UIKit
import Photos
import MobileCoreServices

let IS_IPAD = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.pad
let IS_IPHONE = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.phone
let SCREEN_WIDTH = UIScreen.main.bounds.size.width
let SCREEN_HEIGHT = UIScreen.main.bounds.size.height
let IS_LARGE_SCREEN = IS_IPHONE && max(SCREEN_WIDTH, SCREEN_HEIGHT) >= 736.0

// TODO: Use `@propertyWrapper` for this when it's out.
extension UserDefaults {
	var showedScrollPreview: Bool {
		let key = "__showedScrollPreview__"

		if bool(forKey: key) {
			return false
		} else {
			set(true, forKey: key)
			return true
		}
	}
}

final class ViewController: UIViewController {
	var sourceImage: UIImage?
	var blurAmount: Float = 50
	let stockImages = Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: "Bundled Photos")!
	lazy var randomImageIterator: AnyIterator<URL> = self.stockImages.uniqueRandomElement()

	var workItem: DispatchWorkItem?

	lazy var scrollView = with(UIScrollView()) {
		$0.frame = view.bounds
		$0.bounces = false
		$0.showsHorizontalScrollIndicator = false
		$0.showsVerticalScrollIndicator = false
		$0.contentInsetAdjustmentBehavior = .never
	}

	lazy var imageView = with(UIImageView()) {
		$0.image = UIImage(color: .black, size: view.frame.size)
		$0.contentMode = .scaleAspectFit
		$0.clipsToBounds = true
		$0.frame = view.bounds
	}

	lazy var slider = with(UISlider()) {
		let SLIDER_MARGIN: CGFloat = 120
		$0.frame = CGRect(x: 0, y: 0, width: view.frame.size.width - SLIDER_MARGIN, height: view.frame.size.height)
		$0.minimumValue = 10
		$0.maximumValue = 100
		$0.value = blurAmount
		$0.isContinuous = true
		$0.setThumbImage(UIImage(named: "SliderThumb")!, for: .normal)
		$0.autoresizingMask = [
			.flexibleWidth,
			.flexibleTopMargin,
			.flexibleBottomMargin,
			.flexibleLeftMargin,
			.flexibleRightMargin
		]
		$0.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
	}

	override var canBecomeFirstResponder: Bool {
		return true
	}

	override var prefersStatusBarHidden: Bool {
		return true
	}

	override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
		if motion == .motionShake {
			randomImage()
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		view.addSubview(scrollView)
		scrollView.addSubview(imageView)

		let TOOLBAR_HEIGHT: CGFloat = 80 + window.safeAreaInsets.bottom
		let toolbar = UIToolbar(frame: CGRect(x: 0, y: view.frame.size.height - TOOLBAR_HEIGHT, width: view.frame.size.width, height: TOOLBAR_HEIGHT))
		toolbar.autoresizingMask = .flexibleWidth
		toolbar.alpha = 0.6
		toolbar.tintColor = #colorLiteral(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)

		// Remove background
		toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
		toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)

		// Gradient background
		let GRADIENT_PADDING: CGFloat = 40
		let gradient = CAGradientLayer()
		gradient.frame = CGRect(x: 0, y: -GRADIENT_PADDING, width: toolbar.frame.size.width, height: toolbar.frame.size.height + GRADIENT_PADDING)
		gradient.colors = [
			UIColor.clear.cgColor,
			UIColor.black.withAlphaComponent(0.1).cgColor,
			UIColor.black.withAlphaComponent(0.3).cgColor,
			UIColor.black.withAlphaComponent(0.4).cgColor
		]
		toolbar.layer.addSublayer(gradient)

		toolbar.items = [
			UIBarButtonItem(image: UIImage(named: "PickButton")!, target: self, action: #selector(pickImage), width: 20),
			.flexibleSpace,
			UIBarButtonItem(customView: slider),
			.flexibleSpace,
			UIBarButtonItem(image: UIImage(named: "SaveButton")!, target: self, action: #selector(saveImage), width: 20)
		]
		view.addSubview(toolbar)

		// Important that this is here at the end for the fading to work
		randomImage()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		if UserDefaults.standard.isFirstLaunch {
			let alert = UIAlertController(
				title: "Tip",
				message: "Shake the device to get a random image.",
				preferredStyle: .alert
			)

			alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
				self.previewScrollingToUser()
			})

			self.present(alert, animated: true)
		}
	}

	@objc
	func pickImage() {
		let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

		if UIImagePickerController.isSourceTypeAvailable(.camera) {
			actionSheet.addAction(UIAlertAction(title: "Take photo", style: .default) { _ in
				self.showImagePicker(with: .camera)
			})
		}

		actionSheet.addAction(UIAlertAction(title: "Choose from library", style: .default) { _ in
			self.showImagePicker(with: .photoLibrary)
		})

		actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

		present(actionSheet, animated: true, completion: nil)
	}

	func showImagePicker(with type: UIImagePickerController.SourceType) {
		let picker = UIImagePickerController()
		picker.sourceType = type
		picker.mediaTypes = [kUTTypeImage as String]
		picker.delegate = self
		present(picker, animated: true, completion: nil)
	}

	func blurImage(_ blurAmount: Float) -> UIImage {
		return UIImageEffects.imageByApplyingBlur(
			to: sourceImage,
			withRadius: CGFloat(blurAmount * (IS_LARGE_SCREEN ? 0.8 : 1.2)),
			tintColor: UIColor(white: 1, alpha: CGFloat(max(0, min(0.25, blurAmount * 0.004)))),
			saturationDeltaFactor: CGFloat(max(1, min(2.8, blurAmount * (IS_IPAD ? 0.035 : 0.045)))),
			maskImage: nil
		)
	}

	@objc
	func updateImage() {
		if let workItem = workItem {
			workItem.cancel()
		}

		workItem = DispatchWorkItem {
			let temp = self.blurImage(self.blurAmount)
			DispatchQueue.main.async {
				self.imageView.image = temp
			}
		}

		DispatchQueue.global(qos: .userInteractive).async(execute: workItem!)
	}

	@objc
	func sliderChanged(_ sender: UISlider) {
		blurAmount = sender.value
		updateImage()
	}

	@objc
	func saveImage(_ button: UIBarButtonItem) {
		button.isEnabled = false

		PHPhotoLibrary.save(image: scrollView.toImage(), toAlbum: "Blear") { result in
			button.isEnabled = true

			let HUD = JGProgressHUD(style: .dark)
			HUD.indicatorView = JGProgressHUDSuccessIndicatorView()
			HUD.animation = JGProgressHUDFadeZoomAnimation()
			HUD.vibrancyEnabled = true
			HUD.contentInsets = UIEdgeInsets(all: 30)

			if case .failure(let error) = result {
				HUD.indicatorView = JGProgressHUDErrorIndicatorView()
				HUD.textLabel.text = error.localizedDescription
				HUD.show(in: self.view)
				HUD.dismiss(afterDelay: 3)
				return
			}

			//HUD.indicatorView = JGProgressHUDImageIndicatorView(image: #imageLiteral(resourceName: "HudSaved"))
			HUD.show(in: self.view)
			HUD.dismiss(afterDelay: 0.8)

			// Only on first save
			if UserDefaults.standard.isFirstLaunch {
				delay(seconds: 1) {
					let alert = UIAlertController(
						title: "Changing Wallpaper",
						message: "In the Photos app go to the wallpaper you just saved, tap the action button on the bottom left and choose 'Use as Wallpaper'.",
						preferredStyle: .alert
					)
					alert.addAction(UIAlertAction(title: "OK", style: .default))
					self.present(alert, animated: true)
				}
			}
		}
	}

	func changeImage(_ image: UIImage) {
		let temp = UIImageView(image: scrollView.toImage())
		view.insertSubview(temp, aboveSubview: scrollView)
		let imageViewSize = image.size.aspectFit(to: view.frame.size)
		scrollView.contentSize = imageViewSize
		scrollView.contentOffset = .zero
		imageView.frame = CGRect(origin: .zero, size: imageViewSize)
		imageView.image = image
		sourceImage = image.resized(to: CGSize(width: imageViewSize.width / 2, height: imageViewSize.height / 2))
		updateImage()

		// The delay here is important so it has time to blur the image before we start fading
		UIView.animate(
			withDuration: 0.6,
			delay: 0.3,
			options: .curveEaseInOut,
			animations: {
				temp.alpha = 0
			}, completion: { _ in
				temp.removeFromSuperview()
			}
		)
	}

	func randomImage() {
		changeImage(UIImage(contentsOf: randomImageIterator.next()!)!)
	}

	func previewScrollingToUser() {
		let x = scrollView.contentSize.width - scrollView.frame.size.width
		let y = scrollView.contentSize.height - scrollView.frame.size.height
		scrollView.setContentOffset(CGPoint(x: x, y: y), animated: true)

		delay(seconds: 1) {
			self.scrollView.setContentOffset(.zero, animated: true)
		}
	}
}

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
	func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
		guard let chosenImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else {
			dismiss(animated: true, completion: nil)
			return
		}

		changeImage(chosenImage)
		dismiss(animated: true, completion: nil)
	}

	func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
		dismiss(animated: true, completion: nil)
	}
}
