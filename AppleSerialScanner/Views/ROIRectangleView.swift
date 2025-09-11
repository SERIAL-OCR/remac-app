import SwiftUI

struct ROIRectangleView: View {
    let rect: CGRect
    
    var body: some View {
        Path { path in
            path.addRect(rect)
        }
        .stroke(Color.white, lineWidth: 2)
        .shadow(color: .black.opacity(0.5), radius: 2)
    }
}
