import Foundation

@main
enum CursorAccountsMain {
    static func main() async {
        let code = await AgentCLIRuntime.run(Array(CommandLine.arguments.dropFirst()))
        exit(code)
    }
}
