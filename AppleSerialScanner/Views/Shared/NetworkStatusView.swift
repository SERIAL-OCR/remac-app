import SwiftUI

struct NetworkStatusView: View {
    @ObservedObject var backendService: BackendService
    
    var body: some View {
        if !backendService.networkAvailable || !backendService.isConnected {
            VStack {
                HStack {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.red)
                    
                    Text(backendService.connectionError ?? "Network unavailable")
                        .font(.caption)
                        .foregroundColor(.red)
                    
                    Spacer()
                    
                    Button(action: {
                        Task {
                            _ = await backendService.testConnection()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red, lineWidth: 0.5)
                )
            }
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut, value: backendService.isConnected)
        }
    }
}

struct NetworkStatusView_Previews: PreviewProvider {
    static var previews: some View {
        let backendService = BackendService()
        // Simulate offline state
        backendService.networkAvailable = false
        backendService.connectionError = "Network connection is offline"
        
        return NetworkStatusView(backendService: backendService)
            .previewLayout(.sizeThatFits)
    }
}
