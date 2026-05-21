import Foundation

protocol CommandProviding {
    func results(for query: String) -> [PaletteCommand]
}
