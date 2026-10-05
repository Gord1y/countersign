import ApprovalCore

enum SubagentDescription {
  static func chain(for request: ApprovalRequest) -> [SubagentChainLink]? {
    guard let transcriptPath = request.transcriptPath, let agentID = request.agentID else {
      return nil
    }
    return SubagentChainReader.chain(transcriptPath: transcriptPath, agentID: agentID)
  }

  static func resolve(from chain: [SubagentChainLink]?) -> String? {
    chain?.last?.description
  }
}
