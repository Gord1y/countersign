import ApprovalCore

enum SubagentDescription {
  static func resolve(for request: ApprovalRequest) -> String? {
    guard let transcriptPath = request.transcriptPath, let agentID = request.agentID else {
      return nil
    }
    return SubagentChainReader.chain(transcriptPath: transcriptPath, agentID: agentID)?.last?
      .description
  }
}
