/**
 * Mock Bedrock Server
 * Simulates AWS Bedrock API responses for local development
 *
 * Endpoints:
 * - POST /model/:modelId/invoke - Invoke model (sync)
 * - POST /model/:modelId/invoke-with-response-stream - Invoke model (stream)
 * - GET /health - Health check
 */

const http = require('http');

const PORT = process.env.PORT || 8080;

// Token counting simulation (approximate)
const countTokens = (text) => Math.ceil((text || '').length / 4);

// Model responses based on model ID
const MODEL_RESPONSES = {
  'anthropic.claude-3-5-sonnet-20240620-v1:0': {
    model: 'claude-3-5-sonnet-20240620',
    maxTokens: 8192,
  },
  'anthropic.claude-3-sonnet-20240229-v1:0': {
    model: 'claude-3-sonnet-20240229',
    maxTokens: 4096,
  },
  'anthropic.claude-3-haiku-20240307-v1:0': {
    model: 'claude-3-haiku-20240307',
    maxTokens: 4096,
  },
  'amazon.titan-text-express-v1': {
    model: 'titan-text-express',
    maxTokens: 4096,
  },
};

// Generate mock response
const generateResponse = (modelId, body) => {
  const modelConfig = MODEL_RESPONSES[modelId] || MODEL_RESPONSES['anthropic.claude-3-sonnet-20240229-v1:0'];
  const inputTokens = countTokens(JSON.stringify(body.messages || body.prompt || ''));
  const outputText = `This is a mock response from ${modelConfig.model}. Your request was processed successfully. Input contained approximately ${inputTokens} tokens.`;
  const outputTokens = countTokens(outputText);

  // Claude format response
  if (modelId.startsWith('anthropic.claude')) {
    return {
      id: `msg_mock_${Date.now()}`,
      type: 'message',
      role: 'assistant',
      content: [
        {
          type: 'text',
          text: outputText,
        },
      ],
      model: modelConfig.model,
      stop_reason: 'end_turn',
      usage: {
        input_tokens: inputTokens,
        output_tokens: outputTokens,
      },
    };
  }

  // Titan format response
  if (modelId.startsWith('amazon.titan')) {
    return {
      inputTextTokenCount: inputTokens,
      results: [
        {
          tokenCount: outputTokens,
          outputText: outputText,
          completionReason: 'FINISH',
        },
      ],
    };
  }

  // Generic response
  return {
    output: outputText,
    usage: {
      input_tokens: inputTokens,
      output_tokens: outputTokens,
    },
  };
};

// Parse request body
const parseBody = (req) => {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (chunk) => (body += chunk));
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (e) {
        reject(new Error('Invalid JSON'));
      }
    });
    req.on('error', reject);
  });
};

// Request handler
const handler = async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const path = url.pathname;

  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Amz-Date, X-Amz-Security-Token');

  // Handle preflight
  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  // Health check
  if (path === '/health' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'healthy', timestamp: new Date().toISOString() }));
    return;
  }

  // Model invocation
  const invokeMatch = path.match(/^\/model\/([^/]+)\/invoke(-with-response-stream)?$/);
  if (invokeMatch && req.method === 'POST') {
    const modelId = decodeURIComponent(invokeMatch[1]);
    const isStream = !!invokeMatch[2];

    try {
      const body = await parseBody(req);

      console.log(`[${new Date().toISOString()}] Invoke ${modelId} (stream: ${isStream})`);
      console.log(`  Request: ${JSON.stringify(body).substring(0, 200)}...`);

      // Simulate latency
      await new Promise((resolve) => setTimeout(resolve, 100 + Math.random() * 200));

      const response = generateResponse(modelId, body);

      if (isStream) {
        // Streaming response (simplified)
        res.writeHead(200, {
          'Content-Type': 'application/vnd.amazon.eventstream',
          'Transfer-Encoding': 'chunked',
        });
        res.write(JSON.stringify(response));
        res.end();
      } else {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(response));
      }

      console.log(`  Response: ${JSON.stringify(response.usage || {})}`);
    } catch (error) {
      console.error(`  Error: ${error.message}`);
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(
        JSON.stringify({
          __type: 'ValidationException',
          message: error.message,
        })
      );
    }
    return;
  }

  // 404 for unknown routes
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found', path }));
};

// Start server
const server = http.createServer(handler);
server.listen(PORT, () => {
  console.log(`Mock Bedrock server running on http://localhost:${PORT}`);
  console.log('Available models:');
  Object.keys(MODEL_RESPONSES).forEach((id) => console.log(`  - ${id}`));
});
