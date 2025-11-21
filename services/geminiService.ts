import { GoogleGenAI, Modality } from "@google/genai";

if (!process.env.API_KEY) {
  console.warn("API_KEY environment variable not set. Gemini API calls will fail.");
}

const ai = new GoogleGenAI({ apiKey: process.env.API_KEY! });

// 0. NEW: Enhance the Prompt (Text-to-Text) to improve Image Generation quality
export const enhanceFashionPrompt = async (userPrompt: string, fabrics: string[], embellishments: string[]): Promise<string> => {
  try {
    const response = await ai.models.generateContent({
      model: 'gemini-2.5-flash',
      contents: `
                You are an expert Fashion Technologist and 3D Texture Artist.
                Refine the following fashion description to be used as a prompt for a high-end AI image generator.
                
                User Input: "${userPrompt}"
                Selected Fabrics: ${fabrics.join(', ') || 'Standard fabric'}
                Selected Embellishments: ${embellishments.join(', ') || 'None'}

                Task:
                1. Describe the physical properties of the fabric (sheen, weight, drape, texture).
                2. Describe how light interacts with the embellishments.
                3. Ensure the description implies a photorealistic, high-definition fashion photography style.
                4. Keep it under 100 words.
                
                Output ONLY the enhanced description.
            `,
    });

    return response.text || userPrompt;
  } catch (error) {
    console.error("Error enhancing prompt:", error);
    return userPrompt; // Fallback to original prompt on error
  }
};

// 1. Generate a Realistic Design from a Rough Sketch
export const generateDesignFromSketch = async (sketchBase64: string, prompt: string): Promise<string> => {
  try {
    const response = await ai.models.generateContent({
      model: 'gemini-2.5-flash-image',
      contents: {
        parts: [
          {
            inlineData: {
              data: sketchBase64,
              mimeType: 'image/png',
            },
          },
          {
            text: `Turn this rough sketch into a high-quality, photorealistic clothing item. 
                   
                   Detailed Specification: ${prompt}. 
                   
                   Directives:
                   - Strictly follow the shape and silhouette of the sketch.
                   - Apply the textures described in the specification realistically.
                   - The output must be the clothing item isolated on a clean, neutral background.
                   - High fashion photography lighting.`,
          },
        ],
      },
      config: {
        responseModalities: [Modality.IMAGE],
      },
    });

    for (const part of response.candidates[0].content.parts) {
      if (part.inlineData) {
        return part.inlineData.data;
      }
    }

    throw new Error('No image data found in the Gemini API response.');

  } catch (error) {
    console.error("Error generating design from sketch:", error);
    throw new Error("Failed to visualize design.");
  }
};

// 2. Virtual Try-On (Superimpose Design onto Person)
export const generateVirtualTryOnImage = async (personImageBase64: string, productImageBase64: string): Promise<string> => {
  try {
    const response = await ai.models.generateContent({
      model: 'gemini-2.5-flash-image',
      contents: {
        parts: [
          {
            inlineData: {
              data: personImageBase64,
              mimeType: 'image/jpeg', // Person image
            },
          },
          {
            inlineData: {
              data: productImageBase64,
              mimeType: 'image/png', // Product image
            },
          },
          {
            text: 'Superimpose the clothing item from the second image onto the person in the first image. The result should be a realistic image of the person wearing the clothing. Make sure the clothing fits naturally on the person\'s body proportions and lighting matches.',
          },
        ],
      },
      config: {
        responseModalities: [Modality.IMAGE],
      },
    });

    for (const part of response.candidates[0].content.parts) {
      if (part.inlineData) {
        return part.inlineData.data;
      }
    }

    throw new Error('No image data found in the Gemini API response.');

  } catch (error) {
    console.error("Error calling Gemini API:", error);
    throw new Error("Failed to generate virtual try-on image.");
  }
};

// 3. Magic Makeover (Text Description -> New Outfit on Person)
export const generateMakeoverImage = async (personImageBase64: string, prompt: string): Promise<string> => {
  try {
    const response = await ai.models.generateContent({
      model: 'gemini-2.5-flash-image',
      contents: {
        parts: [
          {
            inlineData: {
              data: personImageBase64,
              mimeType: 'image/jpeg',
            },
          },
          {
            text: `Change the outfit of the person in this image. 
                   New Outfit Description: ${prompt}. 
                   Ensure the face, body pose, lighting, and background remain exactly the same. 
                   Only change the clothing. The result should be photorealistic.`,
          },
        ],
      },
      config: {
        responseModalities: [Modality.IMAGE],
      },
    });

    for (const part of response.candidates[0].content.parts) {
      if (part.inlineData) {
        return part.inlineData.data;
      }
    }

    throw new Error('No image data found in the Gemini API response.');

  } catch (error) {
    console.error("Error calling Gemini API:", error);
    throw new Error("Failed to generate makeover image.");
  }
};

// Helper to strip PII
const stripPII = (data: any): any => {
  if (Array.isArray(data)) {
    return data.map(item => stripPII(item));
  } else if (typeof data === 'object' && data !== null) {
    const { name, email, phone, contact, ...rest } = data; // Remove sensitive fields
    // Recursively strip nested objects
    const sanitized: any = {};
    for (const key in rest) {
      sanitized[key] = stripPII(rest[key]);
    }
    return sanitized;
  }
  return data;
};

// 4. Ask the Boutique Assistant (Text Q&A with Data Context)
export const askBoutiqueAssistant = async (dataContext: any, userQuestion: string): Promise<string> => {
  try {
    // Anonymize data before sending to AI
    const safeContext = JSON.stringify(stripPII(dataContext), null, 2);

    const response = await ai.models.generateContent({
      model: 'gemini-2.5-flash',
      contents: `
                You are the intelligent assistant for a Boutique Owner's management app.
                Here is the current state of the business (anonymized JSON):
                ${safeContext}
                
                Answer the user's question based ONLY on this data. Be concise, professional, and helpful.
                If you need to calculate something (like total revenue or pending orders), do it.
                User Question: "${userQuestion}"
            `,
    });

    return response.text || "I'm sorry, I couldn't process that.";
  } catch (error) {
    console.error("Error asking assistant:", error);
    return "I'm having trouble connecting to the brain right now. Please try again.";
  }
};

// 5. Suggest Accessories (Analyze Image -> Suggest List)
export const suggestAccessories = async (imageBase64: string): Promise<string[]> => {
  try {
    const response = await ai.models.generateContent({
      model: 'gemini-2.5-flash',
      contents: {
        parts: [
          {
            inlineData: {
              data: imageBase64,
              mimeType: 'image/png',
            },
          },
          {
            text: "Analyze this outfit and suggest 3-4 specific accessories that would complete the look. Return ONLY a JSON array of strings, for example: [\"Gold Necklace\", \"Red Clutch\", \"Pearl Earrings\"]. Do not add Markdown.",
          },
        ],
      },
    });
    const text = response.text || "[]";
    try {
      // Sanitize potential markdown blocks if any
      const jsonStr = text.replace(/```json/g, '').replace(/```/g, '').trim();
      return JSON.parse(jsonStr);
    } catch (e) {
      return ["Matching Handbag", "Statement Earrings", "Elegant Watch"];
    }
  } catch (error) {
    console.error("Error suggesting accessories:", error);
    return ["Gold Necklace", "Designer Watch", "Silk Scarf"];
  }
};