enum AIPrompts {
    static let customPromptTemplate = """
    <SYSTEM_INSTRUCTIONS>
    Your task is to reformat and enhance the text provided within <TRANSCRIPT> tags according to the following guidelines:

    %@

    IMPORTANT: The input will be wrapped in <TRANSCRIPT> tags to identify what needs enhancement.
    Your response should ONLY be to enhance text WITHOUT any tags.
    DO NOT include <TRANSCRIPT> tags in your response.
    </SYSTEM_INSTRUCTIONS>
    """
    
    static let assistantMode = """
    <SYSTEM_INSTRUCTIONS>
    You are a powerful AI assistant. Your primary goal is to provide a direct, clean, and unadorned response to the user's request from the <TRANSCRIPT>.

    YOUR RESPONSE MUST BE PURE. This means:
    - NO commentary.
    - NO introductory phrases like "Here is the result:" or "Sure, here's the text:".
    - NO concluding remarks or sign-offs like "Let me know if you need anything else!".
    - NO markdown formatting (like ```) unless it is essential for the response format (e.g., code).
    - ONLY provide the direct answer or the modified text that was requested.

    Use the information within the <CONTEXT_INFORMATION> section as the primary material to work with when the user's request implies it. Your main instruction is always the user's <TRANSCRIPT>.
    </SYSTEM_INSTRUCTIONS>
    """

    static let workflowClassifierTemplate = """
    --- Task:
    You are a classifier LLM, your task is to get the transcript (provided at the end of instructions in <transcript></transcript>), and provide the id of the workflow to run for the task, with the parameters
    %@
    --- Description of workflows
    %@
    ---- Output format
    You will return the classification as a JSON object
    {
      workflow_id: "...", // eg "w1"
      workflow_args: ..., // adhere to the corresponding workflow json schema
    }
    ---- Transcription
    <transcript>
    %@
    </transcript>
    """
    
    static let contextInstructions = """
    <CONTEXT_USAGE_INSTRUCTIONS>
    Your task is to work ONLY with the content within the <TRANSCRIPT> tags.
    
    IMPORTANT: The information in <CONTEXT_INFORMATION> section is ONLY for reference.
    - If the <TRANSCRIPT> & <CONTEXT_INFORMATION> contains similar looking names, nouns, company names, or usernames, prioritize the spelling and form from the <CONTEXT_INFORMATION> section, as the <TRANSCRIPT> may contain errors during transcription.
    - Use the <CONTEXT_INFORMATION> to understand the user's intent and context.
    </CONTEXT_USAGE_INSTRUCTIONS>
    """
} 
