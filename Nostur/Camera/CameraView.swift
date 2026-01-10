//
//  CameraView.swift
//  Nostur
//
//  Created by Rolando Rodriguez on 10/15/20.
//  Created by Fabian Lachman on 29/11/2023.
//

import SwiftUI
import Combine
import AVFoundation
import NavigationBackport

final class CameraModel: ObservableObject {
    private let service = CameraService()
    
    @Published var photo: Photo?
    
    @Published var showAlertError = false
    
    @Published var isFlashOn = false
    
    @Published var willCapturePhoto = false
    
    var alertError: AlertError!
    
    var session: AVCaptureSession
    
    private var subscriptions = Set<AnyCancellable>()
    
    init() {
        self.session = service.session
        
        service.$photo.sink { [weak self] (photo) in
            guard let pic = photo else { return }
            self?.photo = pic
        }
        .store(in: &self.subscriptions)
        
        service.$shouldShowAlertView.sink { [weak self] (val) in
            self?.alertError = self?.service.alertError
            self?.showAlertError = val
        }
        .store(in: &self.subscriptions)
        
        service.$flashMode.sink { [weak self] (mode) in
            self?.isFlashOn = mode == .on
        }
        .store(in: &self.subscriptions)
        
        service.$willCapturePhoto.sink { [weak self] (val) in
            self?.willCapturePhoto = val
        }
        .store(in: &self.subscriptions)
    }
    
    func configure() {
        service.checkForPermissions()
        service.configure()
    }
    
    func capturePhoto() {
        service.capturePhoto()
    }
    
    func flipCamera() {
        service.changeCamera()
    }
    
    func zoom(with factor: CGFloat) {
        service.set(zoom: factor)
    }
    
    func switchFlash() {
        service.flashMode = service.flashMode == .on ? .off : .on
    }
}

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject var model = CameraModel()
    
    @State var currentZoomFactor: CGFloat = 1.0
    private let onUse: (UIImage) -> ()
    
    init(onUse: @escaping (UIImage) -> ()) {
        self.onUse = onUse
    }
    
    var captureButton: some View {
        Button(action: {
            model.capturePhoto()
        }, label: {
            Circle()
                .foregroundColor(.white)
                .frame(width: 80, height: 80, alignment: .center)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.8), lineWidth: 2)
                        .frame(width: 65, height: 65, alignment: .center)
                )
        })
        .padding(10)
    }
    
    var flipCameraButton: some View {
        Button(action: {
            model.flipCamera()
        }, label: {
            Circle()
                .foregroundColor(Color.gray.opacity(0.2))
                .frame(width: 45, height: 45, alignment: .center)
                .overlay(
                    Image(systemName: "camera.rotate.fill")
                        .foregroundColor(.white))
        })
    }
    
    var body: some View {
        GeometryReader { reader in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack {
                    CameraPreview(session: model.session)
                        .gesture(
                            DragGesture().onChanged({ (val) in
                                //  Only accept vertical drag
                                if abs(val.translation.height) > abs(val.translation.width) {
                                    //  Get the percentage of vertical screen space covered by drag
                                    let percentage: CGFloat = -(val.translation.height / reader.size.height)
                                    //  Calculate new zoom factor
                                    let calc = currentZoomFactor + percentage
                                    //  Limit zoom factor to a maximum of 5x and a minimum of 1x
                                    let zoomFactor: CGFloat = min(max(calc, 1), 5)
                                    //  Store the newly calculated zoom factor
                                    currentZoomFactor = zoomFactor
                                    //  Sets the zoom factor to the capture device session
                                    model.zoom(with: zoomFactor)
                                }
                            })
                        )
                        .alert(isPresented: $model.showAlertError, content: {
                            Alert(title: Text(model.alertError.title), message: Text(model.alertError.message), dismissButton: .default(Text(model.alertError.primaryButtonTitle), action: {
                                model.alertError.primaryAction?()
                            }))
                        })
                        .overlay(
                            Group {
                                if model.willCapturePhoto {
                                    Color.black
                                }
                            }
                        )
//                                .animation(.easeInOut)
                        .opacity(model.photo?.image == nil ? 1.0 : 0)
                        .overlay {
                            if let image = model.photo?.image {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
//                                            .animation(.spring())
                                    .toolbar {
                                        ToolbarItem(placement: .primaryAction) {
                                            Button("Use photo", systemImage: "checkmark") {
                                                guard let uiImage = model.photo?.image else { return }
                                                onUse(uiImage)
                                                dismiss()
                                            }
                                        }
                                    }
                                    .animation(.spring(), value: image)
                            }
                        }
                    
                    
                    ZStack {
                        captureButton
                            .offset(y: -10)
                        HStack {
                            if model.photo == nil {
                                Button(action: {
                                    model.switchFlash()
                                }, label: {
                                    Image(systemName: model.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                                        .font(.system(size: 20, weight: .medium, design: .default))
                                        .padding(10)
                                        .contentShape(Rectangle())
                                })
                                .accentColor(model.isFlashOn ? .yellow : .white)
                            }
                            else {
                                Button(action: {
                                    withAnimation {
                                        model.photo = nil
                                    }
                                }, label: {
                                    Text("Retake")
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .padding(10)
                                        .contentShape(Rectangle())
                                })
                            }
                            
                            Spacer()
                            
                            flipCameraButton
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .onAppear {
            model.configure()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    CameraView { imageData in
        
    }
}
