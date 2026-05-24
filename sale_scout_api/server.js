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

  if (!q) return res.status(400).json({ error: 'Missing search query' });

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

      const confidence = smartMatchConfidence(
        q,
        title,
        displaySource,
        extractedPrice
      );

      const suspiciousLowPrice = extractedPrice < 35 && confidence < 90;
      const suspiciousHighPrice = extractedPrice > 350 && confidence < 90;

      if (suspiciousLowPrice || suspiciousHighPrice) continue;
      if (confidence < 35) continue;

      const verificationSignals = buildVerificationSignals(
        q,
        title,
        displaySource,
        extractedPrice,
        confidence
      );

      const deal = {
        title,
        price: Math.round(extractedPrice),
        source: displaySource,
        link: item.link || '',
        thumbnail: item.thumbnail || '',
        confidence,
        verificationSignals,
      };

      const existing = retailerMap[sourceKey];

      if (
        !existing ||
        deal.confidence > existing.confidence ||
        (deal.confidence === existing.confidence && deal.price < existing.price)
      ) {
        retailerMap[sourceKey] = deal;
      }
    }

    const results = Object.values(retailerMap)
      .sort((a, b) => {
        if (b.confidence !== a.confidence) return b.confidence - a.confidence;
        return a.price - b.price;
      })
      .slice(0, 12);

    return res.json({
      query: q,
      resultCount: results.length,
      source: 'serpapi_verification_signals_v5',
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
  if (cleaned.includes('goat')) return 'goat';
  if (cleaned.includes('stockx')) return 'stockx';
  if (cleaned.includes('ebay')) return 'ebay';
  if (cleaned.includes('poshmark')) return 'poshmark';
  if (cleaned.includes('mercari')) return 'mercari';
  if (cleaned.includes('whatnot')) return 'whatnot';
  if (cleaned.includes('sidelineswap')) return 'sidelineswap';

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
    goat: 'GOAT',
    stockx: 'StockX',
    ebay: 'eBay',
    poshmark: 'Poshmark',
    mercari: 'Mercari',
    whatnot: 'Whatnot',
    sidelineswap: 'SidelineSwap',
  };

  return displayNames[key] || String(source || '').replace(/\s+/g, ' ').trim();
}

function extractSkuFromText(text) {
  const value = String(text || '').toUpperCase();
  const matches = value.match(/\b[A-Z0-9]{6}-[0-9]{3}\b/g);

  if (!matches || matches.length === 0) return null;

  return matches.find((m) => !m.startsWith('HTTP')) || matches[0];
}

function containsAny(text, words) {
  return words.some((word) => text.includes(word));
}

function smartMatchConfidence(query, title, source, price) {
  const queryText = String(query || '').toLowerCase();
  const titleText = String(title || '').toLowerCase();
  const sourceText = String(source || '').toLowerCase();

  const querySku = extractSkuFromText(query);
  const titleSku = extractSkuFromText(title);

  let score = 0;

  if (querySku && titleSku && querySku === titleSku) score += 55;
  if (querySku && titleText.includes(querySku.toLowerCase())) score += 45;

  const importantWords = queryText
    .replace(/[^a-z0-9\s-]/g, '')
    .split(/\s+/)
    .filter((word) => word.length > 2)
    .filter(
      (word) =>
        !['mens', 'womens', 'men', 'women', 'shoes', 'shoe', 'nike'].includes(
          word
        )
    );

  let matchedWords = 0;

  for (const word of importantWords) {
    if (titleText.includes(word)) matchedWords++;
  }

  if (importantWords.length > 0) {
    score += Math.round((matchedWords / importantWords.length) * 35);
  }

  if (queryText.includes('nike') && titleText.includes('nike')) score += 10;
  if (queryText.includes('air max') && titleText.includes('air max')) score += 10;
  if (queryText.includes('dunk') && titleText.includes('dunk')) score += 10;
  if (queryText.includes('force') && titleText.includes('force')) score += 10;

  if (sourceText.includes('nike')) score += 8;
  if (sourceText.includes('finish')) score += 5;
  if (sourceText.includes('dick')) score += 5;
  if (sourceText.includes('goat') || sourceText.includes('stockx')) score += 3;

  score += genericIdentityAdjustment(queryText, titleText, price);

  return Math.max(0, Math.min(100, score));
}

function genericIdentityAdjustment(queryText, titleText, price) {
  let adjustment = 0;

  const childTerms = ['kids', 'kid', 'baby', 'toddler', 'youth', 'grade school', 'gs'];
  const usedTerms = ['used', 'pre-owned', 'preowned', 'worn', 'second hand'];
  const bundleTerms = ['bundle', 'lot of', 'pack of', '2-pack', '3-pack', '4-pack'];

  if (!containsAny(queryText, childTerms) && containsAny(titleText, childTerms)) {
    adjustment -= 25;
  }

  if (!containsAny(queryText, usedTerms) && containsAny(titleText, usedTerms)) {
    adjustment -= 18;
  }

  if (!containsAny(queryText, bundleTerms) && containsAny(titleText, bundleTerms)) {
    adjustment -= 12;
  }

  if (queryText.includes('men') && titleText.includes('women')) {
    adjustment -= 18;
  }

  if (queryText.includes('women') && titleText.includes('men')) {
    adjustment -= 18;
  }

  if (queryText.includes('low') && titleText.includes('high')) {
    adjustment -= 18;
  }

  if (queryText.includes('high') && titleText.includes('low')) {
    adjustment -= 18;
  }

  if (queryText.includes('mid') && (titleText.includes('low') || titleText.includes('high'))) {
    adjustment -= 10;
  }

  if (price < 20) adjustment -= 20;

  return adjustment;
}

function buildVerificationSignals(query, title, source, price, confidence) {
  const queryText = String(query || '').toLowerCase();
  const titleText = String(title || '').toLowerCase();
  const sourceText = String(source || '').toLowerCase();

  const signals = [];
  const warnings = [];

  const querySku = extractSkuFromText(query);
  const titleSku = extractSkuFromText(title);

  if (querySku && titleSku && querySku === titleSku) {
    signals.push('SKU match');
  } else if (querySku && titleText.includes(querySku.toLowerCase())) {
    signals.push('SKU found in title');
  } else if (querySku) {
    warnings.push('SKU not confirmed');
  }

  if (queryText.includes('nike') && titleText.includes('nike')) {
    signals.push('Brand match');
  }

  if (queryText.includes('dunk') && titleText.includes('dunk')) {
    signals.push('Model match');
  }

  if (queryText.includes('air max') && titleText.includes('air max')) {
    signals.push('Model match');
  }

  if (queryText.includes('force') && titleText.includes('force')) {
    signals.push('Model match');
  }

  if (queryText.includes('low') && titleText.includes('low')) {
    signals.push('Low-top match');
  }

  if (queryText.includes('high') && titleText.includes('high')) {
    signals.push('High-top match');
  }

  if (queryText.includes('men') && titleText.includes('men')) {
    signals.push("Men's match");
  }

  if (queryText.includes('women') && titleText.includes('women')) {
    signals.push("Women's match");
  }

  if (sourceText.includes('nike')) {
    signals.push('Official retailer');
  } else if (
    sourceText.includes('finish') ||
    sourceText.includes('dick') ||
    sourceText.includes('jdsports') ||
    sourceText.includes('snipes')
  ) {
    signals.push('Known retailer');
  } else if (sourceText.includes('goat') || sourceText.includes('stockx')) {
    signals.push('Sneaker marketplace');
  }

  if (queryText.includes('men') && titleText.includes('women')) {
    warnings.push('Gender mismatch risk');
  }

  if (queryText.includes('women') && titleText.includes('men')) {
    warnings.push('Gender mismatch risk');
  }

  if (queryText.includes('low') && titleText.includes('high')) {
    warnings.push('Silhouette mismatch risk');
  }

  if (queryText.includes('high') && titleText.includes('low')) {
    warnings.push('Silhouette mismatch risk');
  }

  if (
    titleText.includes('kids') ||
    titleText.includes('youth') ||
    titleText.includes('toddler') ||
    titleText.includes('grade school') ||
    titleText.includes(' gs ')
  ) {
    if (
      !queryText.includes('kids') &&
      !queryText.includes('youth') &&
      !queryText.includes('toddler') &&
      !queryText.includes('grade school') &&
      !queryText.includes(' gs ')
    ) {
      warnings.push('Age group mismatch risk');
    }
  }

  if (
    titleText.includes('used') ||
    titleText.includes('pre-owned') ||
    titleText.includes('preowned')
  ) {
    warnings.push('Condition mismatch risk');
  }

  if (price < 35 && confidence < 90) {
    warnings.push('Suspiciously low price');
  }

  if (confidence >= 80) {
    signals.push('High-confidence match');
  } else if (confidence >= 50) {
    signals.push('Possible match');
  } else {
    warnings.push('Low-confidence match');
  }

  return {
    positive: [...new Set(signals)].slice(0, 5),
    warnings: [...new Set(warnings)].slice(0, 5),
  };
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
