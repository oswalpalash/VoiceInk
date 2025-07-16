import Foundation
import Combine
import os

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let b = try? container.decode(Bool.self) {
            self = .boolean(b)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .boolean(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }

    var value: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .boolean(let b): return b
        case .object(let o): return o.mapValues { $0.value }
        case .array(let a): return a.map { $0.value }
        case .null: return NSNull()
        }
    }
}

struct WorkflowResponse: Decodable {
    let workflow_id: String
    let workflow_args: [String: Any]

    enum CodingKeys: String, CodingKey { case workflow_id, workflow_args }

    init(workflow_id: String, workflow_args: [String: Any]) {
        self.workflow_id = workflow_id
        self.workflow_args = workflow_args
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workflow_id = try container.decode(String.self, forKey: .workflow_id)
        let raw = try container.decode([String: JSONValue].self, forKey: .workflow_args)
        workflow_args = raw.mapValues { $0.value }
    }
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
}

class WorkflowManager: ObservableObject {
    static let shared = WorkflowManager()

    private let logger = Logger(subsystem: "com.prakashjoshipax.VoiceInk", category: "workflow")

    @Published var workflows: [Workflow] = []
    @Published var errorMessage: String?

    private let workflowsKey = "VoiceInkWorkflows"

    private init() {
        loadWorkflows()
    }

    func addWorkflow(_ workflow: Workflow) {
        workflows.append(workflow)
        saveWorkflows()
    }

    func updateWorkflow(_ workflow: Workflow) {
        if let idx = workflows.firstIndex(where: { $0.id == workflow.id }) {
            workflows[idx] = workflow
            saveWorkflows()
        }
    }

    func deleteWorkflow(withID id: UUID) {
        workflows.removeAll { $0.id == id }
        saveWorkflows()
    }

    func getWorkflow(withID id: UUID) -> Workflow? {
        workflows.first { $0.id == id }
    }

    // MARK: persistence
    private func saveWorkflows() {
        do {
            let data = try JSONEncoder().encode(workflows)
            UserDefaults.standard.set(data, forKey: workflowsKey)
        } catch { logger.error("Error saving workflows: \(error.localizedDescription)") }
    }

    private func loadWorkflows() {
        guard let data = UserDefaults.standard.data(forKey: workflowsKey) else { return }
        do {
            workflows = try JSONDecoder().decode([Workflow].self, from: data)
        } catch {
            logger.error("Error loading workflows: \(error.localizedDescription)")
            workflows = []
        }
    }

    // MARK: execution
    func executeWorkflow(fromResponse jsonResponse: String) {
        logger.notice("attempting workflow from response: \(jsonResponse, privacy: .public)")
        guard let data = jsonResponse.data(using: .utf8) else {
            let msg = "Failed to convert workflow response to data"
            logger.error("\(msg)")
            errorMessage = msg
            return
        }
        do {
            if let resp = try? JSONDecoder().decode(WorkflowResponse.self, from: data) {
                processWorkflowResponse(resp)
            } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = json["workflow_id"] as? String,
                      let args = json["workflow_args"] as? [String: Any] {
                processWorkflowResponse(WorkflowResponse(workflow_id: id, workflow_args: args))
            } else {
                let msg = "JSON structure doesn't match the expected workflow format"
                logger.error("\(msg)")
                errorMessage = msg
            }
        } catch {
            let msg = "Error parsing workflow response: \(error.localizedDescription)"
            logger.error("\(msg)")
            errorMessage = msg
        }
    }

    private func processWorkflowResponse(_ response: WorkflowResponse) {
        guard let idx = Int(response.workflow_id.dropFirst(1)) else {
            let msg = "Invalid workflow ID format: \(response.workflow_id)"
            logger.error("\(msg)")
            errorMessage = msg
            return
        }
        let arrayIndex = idx - 1
        guard arrayIndex >= 0 && arrayIndex < workflows.count else {
            let msg = "Workflow index out of bounds: \(arrayIndex). You might need to redefine your workflows."
            logger.error("\(msg)")
            errorMessage = msg
            return
        }
        let workflow = workflows[arrayIndex]
        logger.notice("found workflow: \(workflow.name, privacy: .public)")
        guard !workflow.shellScriptPath.isEmpty else {
            let msg = "No shell script path specified for workflow '\(workflow.name)'. This is required."
            logger.error("\(msg)")
            errorMessage = msg
            return
        }
        executeShellScript(workflow: workflow, args: response.workflow_args)
    }

    private func executeShellScript(workflow: Workflow, args: [String: Any]) {
        let path = workflow.shellScriptPath
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            let msg = "Shell script does not exist at path: \(path)"
            logger.error("\(msg)")
            errorMessage = msg
            return
        }
        var attrs: [FileAttributeKey: Any] = [:]
        do { attrs = try fm.attributesOfItem(atPath: path) } catch {
            let msg = "Error checking script permissions: \(error.localizedDescription)"
            logger.error("\(msg)")
            errorMessage = msg
            return
        }
        if let perm = attrs[.posixPermissions] as? NSNumber, (perm.intValue & 0o100) == 0 {
            let msg = "Shell script is not executable: \(path)"
            logger.error("\(msg)")
            errorMessage = msg
            return
        }

        var environment = ProcessInfo.processInfo.environment
        if let jsonData = try? JSONSerialization.data(withJSONObject: args),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            environment["WORKFLOW_ARGS"] = jsonString
            logger.notice("setting WORKFLOW_ARGS: \(jsonString, privacy: .public)")
        }
        for (key, value) in args {
            let envKey = "WORKFLOW_ARG_\(key.uppercased())"
            let strVal: String
            if let str = value as? String { strVal = str }
            else if let bool = value as? Bool { strVal = bool ? "true" : "false" }
            else if let num = value as? NSNumber { strVal = num.stringValue }
            else if let arr = value as? [Any],
                    let d = try? JSONSerialization.data(withJSONObject: arr),
                    let s = String(data: d, encoding: .utf8) { strVal = s }
            else if let dict = value as? [String: Any],
                    let d = try? JSONSerialization.data(withJSONObject: dict),
                    let s = String(data: d, encoding: .utf8) { strVal = s }
            else { strVal = "\(value)" }
            environment[envKey] = strVal
            logger.notice("setting \(envKey, privacy: .public): \(strVal, privacy: .public)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [path]
        process.environment = environment
        let outPipe = Pipe(); process.standardOutput = outPipe
        let errPipe = Pipe(); process.standardError = errPipe
        do {
            logger.notice("executing shell script: \(path, privacy: .public)")
            try process.run()
            let outputData = outPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                logger.notice("Script output: \(output, privacy: .public)")
            }
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            if let err = String(data: errData, encoding: .utf8), !err.isEmpty {
                logger.error("Script error: \(err, privacy: .public)")
                errorMessage = "Script error: \(err)"
            }
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                errorMessage = nil
                logger.notice("Script executed successfully")
            } else {
                let msg = "Script '\(workflow.name)' failed with status: \(process.terminationStatus)"
                logger.error("\(msg, privacy: .public)")
                errorMessage = msg
            }
        } catch {
            let msg = "Failed to execute script: \(error.localizedDescription)"
            logger.error("\(msg, privacy: .public)")
            errorMessage = msg
        }
    }
}
