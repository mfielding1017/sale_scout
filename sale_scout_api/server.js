const express = require('express');
const cors = require('cors');

process.env.PLAYWRIGHT_BROWSERS_PATH = '0';

const { chromium } = require('playwright');

const app = express();
app.use(cors());

const PORT = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({ status: 'ok', message: 'Sale Scout API Running' });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.get('/product', async (req, res) => {
  const url = req.query.url;

  if (!url) return res.status(400).json({ error: 'Missing product URL' });

  try {
    const product = await scrapeNike(url);

    console.log({
      title: product.title,
      sku: product.sku,
      currentPrice: product.currentPrice,
      originalPrice: product.originalPrice,
      source: product.source,
    });

    return res.json(product);
  } catch (error) {
    console.error('PRODUCT ERROR:', error.message);

    return res.status(500).json({
      error: 'Failed to fetch product',
      details: error.message,
    });
  }
});

app.get('/search-deals', async (req, res) => {
  const q = req.query.q;

  if (!q) {
    return res.status(400).json({ error: 'Missing search query' });
  }

  try {
    const apiKey = process.env.SERPAPI_KEY;

    if (!apiKey) {
      return res.status(500).json({
        error: 'SERPAPI_KEY missing from environment variables',
      });
    }

    const serpUrl =
      `https://serpapi.com/search.json` +
      `?engine=google_shopping` +
      `&q=${encodeURIComponent(q)}` +
      `&api_key=${apiKey}`;

    const response = await fetch(serpUrl);
    const data = await response.json();

    const rawResults = data.shopping_results || [];
    const retailerMap = {};

    for (const item of rawResults) {
      const title = item.title || '';
      const rawSource = item.source || 'Unknown';
      const sourceKey = normalizeRetailerSource(rawSource);
      const displaySource = cleanRetailerDisplayName(rawSource);

      const extractedPrice =
        typeof item.extracted_price === 'number'
          ? item.extracted_price
          : typeof item.price === 'number'
            ? item.price
            : parseFloat(
                String(item.price || '').replace('$', '').replace(',', '')
              );

      if (!title || !displaySource || !sourceKey || !extractedPrice) continue;

      const confidence = basicMatchConfidence(q, title);
      if (confidence < 45) continue;

      const deal = {
        title,
        price: Math.round(extractedPrice),
        source: displaySource,
        link: item.link || '',
        thumbnail: item.thumbnail || '',
        confidence,
      };

      const existing = retailerMap[sourceKey];

      if (!existing || deal.price < existing.price) {
        retailerMap[sourceKey] = deal;
      }
    }

    const results = Object.values(retailerMap)
      .sort((a, b) => a.price - b.price)
      .slice(0, 8);

    return res.json({
      query: q,
      resultCount: results.length,
      source: 'serpapi_retailer_dedup_v3',
      results,
    });
  } catch (error) {
    console.error('SEARCH DEALS ERROR:', error.message);

    return res.status(500).json({
      error: 'Failed to search deals',
      details: error.message,
    });
  }
});

function normalizeRetailerSource(source) {
  const cleaned = String(source || '')
    .toLowerCase()
    .replace(/\.com/g, '')
    .replace(/[^a-z0-9]/g, '')
    .trim();

  if (cleaned.includes('nike')) return 'nike';
  if (cleaned.includes('finishline')) return 'finishline';
  if (cleaned.includes('dicks') || cleaned.includes('dickssportinggoods')) {
    return 'dickssportinggoods';
  }
  if (cleaned.includes('jdsports')) return 'jdsports';
  if (cleaned.includes('snipes')) return 'snipes';

  return cleaned;
}

function cleanRetailerDisplayName(source) {
  const key = normalizeRetailerSource(source);

  const displayNames = {
    nike: 'Nike',
    finishline: 'Finish Line',
    dickssportinggoods: "Dick's Sporting Goods",
    jdsports: 'JD Sports',
    snipes: 'SNIPES USA',
  };

  return displayNames[key] || String(source || '').replace(/\s+/g, ' ').trim();
}

function basicMatchConfidence(query, title) {
  const queryWords = String(query || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, '')
    .split(/\s+/)
    .filter((word) => word.length > 2);

  if (queryWords.length === 0) return 0;

  const titleText = String(title || '').toLowerCase();
  let score = 0;

  for (const word of queryWords) {
    if (titleText.includes(word)) score++;
  }

  return Math.round((score / queryWords.length) * 100);
}

function cleanPrice(value) {
  if (!value) return null;

  const match = String(value)
    .replace(/,/g, '')
    .match(/\$?\s?([0-9]+(?:\.[0-9]{1,2})?)/);

  if (!match) return null;

  const price = Math.round(Number(match[1]));

  if (!price || price < 5 || price > 1000) return null;

  return price;
}

function cleanText(value) {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

function cleanNikeTitle(title) {
  return cleanText(title)
    .replace('| Nike', '')
    .replace('| Nike.com', '')
    .replace('. Nike.com', '')
    .trim();
}

function extractSkuFromText(text) {
  const value = String(text || '').toUpperCase();
  const matches = value.match(/\b[A-Z0-9]{6}-[0-9]{3}\b/g);

  if (!matches || matches.length === 0) return null;

  for (const match of matches) {
    if (!match.startsWith('HTTP') && !match.startsWith('HTTPS')) {
      return match;
    }
  }

  return matches[0];
}

async function scrapeNike(url) {
  let browser;

  try {
    browser = await chromium.launch({
      headless: true,
      args: [
        '--disable-dev-shm-usage',
        '--disable-gpu',
        '--no-sandbox',
        '--disable-setuid-sandbox',
      ],
    });

    const page = await browser.newPage({
      viewport: { width: 1200, height: 900 },
      userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36',
    });

    await page.route('**/*', (route) => {
      const type = route.request().resourceType();

      if (['image', 'font', 'media'].includes(type)) {
        route.abort();
      } else {
        route.continue();
      }
    });

    await page.goto(url, {
      waitUntil: 'domcontentloaded',
      timeout: 90000,
    });

    await page.waitForTimeout(5000);

    const result = await page.evaluate(() => {
      const getMeta = (name) => {
        const el =
          document.querySelector(`meta[property="${name}"]`) ||
          document.querySelector(`meta[name="${name}"]`);

        return el ? el.getAttribute('content') : '';
      };

      const title =
        getMeta('og:title') ||
        document.querySelector('h1')?.innerText ||
        document.title ||
        'Nike Product';

      const imageUrl = getMeta('og:image') || getMeta('twitter:image') || '';

      const currentPriceEl =
        document.querySelector('[data-testid="currentPrice-container"]') ||
        document.querySelector('[data-test="currentPrice-container"]');

      const originalPriceEl =
        document.querySelector('[data-testid="initialPrice-container"]') ||
        document.querySelector('[data-test="initialPrice-container"]');

      const currentPriceText = currentPriceEl
        ? currentPriceEl.innerText || currentPriceEl.textContent || ''
        : '';

      const originalPriceText = originalPriceEl
        ? originalPriceEl.innerText || originalPriceEl.textContent || ''
        : '';

      const visiblePriceCandidates = Array.from(
        document.querySelectorAll('body *')
      )
        .map((el) => {
          const rect = el.getBoundingClientRect();

          return {
            text: (el.innerText || el.textContent || '').trim(),
            visible:
              rect.width > 0 &&
              rect.height > 0 &&
              rect.top >= 0 &&
              rect.top < 900,
          };
        })
        .filter((item) => item.visible)
        .filter((item) => item.text.includes('$'))
        .filter((item) => item.text.length <= 100);

      const pageText = `${
        document.body.innerText || ''
      } ${document.documentElement.innerHTML || ''}`.toUpperCase();

      const skuMatch =
        pageText.match(/\b[A-Z0-9]{6}-[0-9]{3}\b/) ||
        pageText.match(/\b[A-Z]{2}[0-9]{4}-[0-9]{3}\b/);

      return {
        title,
        imageUrl,
        currentPriceText,
        originalPriceText,
        visiblePriceCandidates,
        sku: skuMatch ? skuMatch[0] : null,
      };
    });

    const currentPrice = cleanPrice(result.currentPriceText);
    const originalPrice = cleanPrice(result.originalPriceText);

    let finalCurrentPrice = currentPrice;
    let finalOriginalPrice = originalPrice;

    if (!finalCurrentPrice) {
      const fallbackPrices = result.visiblePriceCandidates
        .map((item) => cleanPrice(item.text))
        .filter((price) => price !== null);

      const uniquePrices = [...new Set(fallbackPrices)].sort((a, b) => a - b);

      finalCurrentPrice = uniquePrices[0] || 0;
      finalOriginalPrice =
        uniquePrices.length > 1 ? uniquePrices[uniquePrices.length - 1] : null;
    }

    const finalSku = result.sku || extractSkuFromText(url);

    return {
      title: cleanNikeTitle(result.title),
      sku: finalSku,
      retailer: 'Nike',
      currentPrice: finalCurrentPrice || 0,
      originalPrice:
        finalOriginalPrice && finalOriginalPrice > finalCurrentPrice
          ? finalOriginalPrice
          : null,
      originalPriceAvailable: Boolean(
        finalOriginalPrice && finalOriginalPrice > finalCurrentPrice
      ),
      imageUrl: result.imageUrl || '',
      source: 'nike_sku_detection_v1',
    };
  } finally {
    if (browser) {
      try {
        await browser.close();
      } catch (closeError) {
        console.error('Browser close failed:', closeError.message);
      }
    }
  }
}

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
