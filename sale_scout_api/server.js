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

  if (!url) {
    return res.status(400).json({
      error: 'Missing product URL',
    });
  }

  try {
    let product;

    if (url.includes('nike.com')) {
      product = await scrapeNike(url);
    } else {
      return res.status(400).json({
        error: 'Unsupported retailer for now',
      });
    }

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
    return res.status(400).json({
      error: 'Missing search query',
    });
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
                String(item.price || '')
                  .replace('$', '')
                  .replace(',', '')
              );

      if (!title || !displaySource || !sourceKey || !extractedPrice) {
        continue;
      }

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

      const fallbackSearchLink =
        `https://www.google.com/search?tbm=shop&q=${encodeURIComponent(
          `${title} ${displaySource}`
        )}`;

      const querySku = extractSkuFromText(q);
      const titleSku = extractSkuFromText(title);
      const titleText = title.toLowerCase();
      const queryText = q.toLowerCase();

      const verificationSignals = {
        positive: [],
        warnings: [],
      };

      if (querySku && titleSku && querySku === titleSku) {
        verificationSignals.positive.push('SKU match');
      }

      if (titleText.includes('nike')) {
        verificationSignals.positive.push('Brand match');
      }

      if (titleText.includes('dunk')) {
        verificationSignals.positive.push('Model match');
      }

      if (titleText.includes('low')) {
        verificationSignals.positive.push('Low-top match');
      }

      if (
        titleText.includes('men') ||
        titleText.includes("men's") ||
        titleText.includes('mens')
      ) {
        verificationSignals.positive.push("Men's match");
      }

      if (confidence >= 80) {
        verificationSignals.positive.push('High-confidence match');
      }

      if (!querySku || !titleSku || querySku !== titleSku) {
        verificationSignals.warnings.push('SKU not confirmed');
      }

      if (confidence < 60) {
        verificationSignals.warnings.push('Low-confidence match');
      }

      if (
        titleText.includes('kids') ||
        titleText.includes('grade school') ||
        titleText.includes('gs') ||
        titleText.includes('youth') ||
        titleText.includes('toddler') ||
        titleText.includes('baby')
      ) {
        verificationSignals.warnings.push('Age group mismatch risk');
      }

      if (
        titleText.includes('women') &&
        (queryText.includes('men') || queryText.includes("men's"))
      ) {
        verificationSignals.warnings.push('Gender mismatch risk');
      }

      if (
        titleText.includes('used') ||
        titleText.includes('pre-owned') ||
        titleText.includes('preowned')
      ) {
        verificationSignals.warnings.push('Condition mismatch risk');
      }

      const deal = {
        title,
        price: Math.round(extractedPrice),
        source: displaySource,
        link:
          item.link ||
          item.product_link ||
          item.productLink ||
          item.serpapi_link ||
          item.serpapiLink ||
          item.serpapi_product_api ||
          fallbackSearchLink,
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
      source: 'target_support_v1',
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
  if (cleaned.includes('target')) return 'target';
  if (cleaned.includes('walmart')) return 'walmart';
  if (cleaned.includes('costco')) return 'costco';
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
    target: 'Target',
    walmart: 'Walmart',
    costco: 'Costco',
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

  if (!matches || matches.length === 0) {
    return null;
  }

  return matches.find((m) => !m.startsWith('HTTP')) || matches[0];
}

function smartMatchConfidence(query, title, source, price) {
  const queryText = String(query || '').toLowerCase();
  const titleText = String(title || '').toLowerCase();
  const sourceText = String(source || '').toLowerCase();

  const querySku = extractSkuFromText(query);
  const titleSku = extractSkuFromText(title);

  let score = 0;

  if (querySku && titleSku && querySku === titleSku) {
    score += 55;
  }

  if (
    querySku &&
    titleText.includes(querySku.toLowerCase())
  ) {
    score += 45;
  }

  const importantWords = queryText
    .replace(/[^a-z0-9\s-]/g, '')
    .split(/\s+/)
    .filter((word) => word.length > 2)
    .filter(
      (word) =>
        ![
          'mens',
          'womens',
          'men',
          'women',
          'shoes',
          'shoe',
          'nike',
          'target',
          'walmart',
          'costco',
        ].includes(word)
    );

  let matchedWords = 0;

  for (const word of importantWords) {
    if (titleText.includes(word)) {
      matchedWords++;
    }
  }

  if (importantWords.length > 0) {
    score += Math.round(
      (matchedWords / importantWords.length) * 45
    );
  }

  if (
    queryText.includes('nike') &&
    titleText.includes('nike')
  ) {
    score += 10;
  }

  if (
    queryText.includes('target') &&
    sourceText.includes('target')
  ) {
    score += 10;
  }

  if (
    queryText.includes('walmart') &&
    sourceText.includes('walmart')
  ) {
    score += 10;
  }

  if (
    queryText.includes('costco') &&
    sourceText.includes('costco')
  ) {
    score += 10;
  }

  if (
    queryText.includes('air max') &&
    titleText.includes('air max')
  ) {
    score += 10;
  }

  if (
    queryText.includes('dunk') &&
    titleText.includes('dunk')
  ) {
    score += 10;
  }

  if (
    queryText.includes('force') &&
    titleText.includes('force')
  ) {
    score += 10;
  }

  if (sourceText.includes('target')) score += 8;
  if (sourceText.includes('walmart')) score += 8;
  if (sourceText.includes('costco')) score += 8;
  if (sourceText.includes('nike')) score += 8;

  if (
    titleText.includes('kids') ||
    titleText.includes('baby') ||
    titleText.includes('toddler')
  ) {
    score -= 15;
  }

  if (
    titleText.includes('used') ||
    titleText.includes('pre-owned')
  ) {
    score -= 18;
  }

  if (
    titleText.includes('refurbished') ||
    titleText.includes('renewed') ||
    titleText.includes('open box')
  ) {
    score -= 20;
  }

  if (price < 2) {
    score -= 20;
  }

  return Math.max(0, Math.min(100, score));
}

function cleanPrice(value) {
  if (!value) return null;

  const match = String(value)
    .replace(/,/g, '')
    .match(/\$?\s?([0-9]+(?:\.[0-9]{1,2})?)/);

  if (!match) return null;

  const price = Math.round(Number(match[1]));

  if (!price || price < 1 || price > 5000) {
    return null;
  }

  return price;
}

function cleanText(value) {
  return String(value || '')
    .replace(/\s+/g, ' ')
    .trim();
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
      viewport: {
        width: 1200,
        height: 900,
      },

      userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36',
    });

    await page.route('**/*', (route) => {
      const type = route.request().resourceType();

      if (
        ['image', 'font', 'media'].includes(type)
      ) {
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
          document.querySelector(
            `meta[property="${name}"]`
          ) ||
          document.querySelector(
            `meta[name="${name}"]`
          );

        return el
          ? el.getAttribute('content')
          : '';
      };

      const title =
        getMeta('og:title') ||
        document.querySelector('h1')
          ?.innerText ||
        document.title ||
        'Nike Product';

      const imageUrl =
        getMeta('og:image') ||
        getMeta('twitter:image') ||
        '';

      const currentPriceEl =
        document.querySelector(
          '[data-testid="currentPrice-container"]'
        ) ||
        document.querySelector(
          '[data-test="currentPrice-container"]'
        );

      const originalPriceEl =
        document.querySelector(
          '[data-testid="initialPrice-container"]'
        ) ||
        document.querySelector(
          '[data-test="initialPrice-container"]'
        );

      const currentPriceText =
        currentPriceEl
          ? currentPriceEl.innerText ||
            currentPriceEl.textContent ||
            ''
          : '';

      const originalPriceText =
        originalPriceEl
          ? originalPriceEl.innerText ||
            originalPriceEl.textContent ||
            ''
          : '';

      const visiblePriceCandidates =
        Array.from(
          document.querySelectorAll('body *')
        )
          .map((el) => {
            const rect =
              el.getBoundingClientRect();

            return {
              text:
                (
                  el.innerText ||
                  el.textContent ||
                  ''
                ).trim(),

              visible:
                rect.width > 0 &&
                rect.height > 0 &&
                rect.top >= 0 &&
                rect.top < 900,
            };
          })
          .filter((item) => item.visible)
          .filter((item) =>
            item.text.includes('$')
          )
          .filter(
            (item) => item.text.length <= 100
          );

      const pageText = `${
        document.body.innerText || ''
      } ${
        document.documentElement.innerHTML || ''
      }`.toUpperCase();

      const skuMatch =
        pageText.match(
          /\b[A-Z0-9]{6}-[0-9]{3}\b/
        ) ||
        pageText.match(
          /\b[A-Z]{2}[0-9]{4}-[0-9]{3}\b/
        );

      return {
        title,
        imageUrl,
        currentPriceText,
        originalPriceText,
        visiblePriceCandidates,
        sku: skuMatch ? skuMatch[0] : null,
      };
    });

    const currentPrice = cleanPrice(
      result.currentPriceText
    );

    const originalPrice = cleanPrice(
      result.originalPriceText
    );

    let finalCurrentPrice = currentPrice;
    let finalOriginalPrice = originalPrice;

    if (!finalCurrentPrice) {
      const fallbackPrices =
        result.visiblePriceCandidates
          .map((item) =>
            cleanPrice(item.text)
          )
          .filter(
            (price) => price !== null
          );

      const uniquePrices = [
        ...new Set(fallbackPrices),
      ].sort((a, b) => a - b);

      finalCurrentPrice =
        uniquePrices[0] || 0;

      finalOriginalPrice =
        uniquePrices.length > 1
          ? uniquePrices[
              uniquePrices.length - 1
            ]
          : null;
    }

    const finalSku =
      result.sku ||
      extractSkuFromText(url);

    return {
      title: cleanNikeTitle(result.title),
      sku: finalSku,
      retailer: 'Nike',
      currentPrice:
        finalCurrentPrice || 0,

      originalPrice:
        finalOriginalPrice &&
        finalOriginalPrice >
          finalCurrentPrice
          ? finalOriginalPrice
          : null,

      originalPriceAvailable:
        Boolean(
          finalOriginalPrice &&
            finalOriginalPrice >
              finalCurrentPrice
        ),

      imageUrl: result.imageUrl || '',

      source: 'nike_sku_detection_v1',
    };
  } finally {
    if (browser) {
      try {
        await browser.close();
      } catch (closeError) {
        console.error(
          'Browser close failed:',
          closeError.message
        );
      }
    }
  }
}

async function scrapeTarget(url) {
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
      viewport: {
        width: 1200,
        height: 900,
      },

      userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36',
    });

    await page.route('**/*', (route) => {
      const type = route.request().resourceType();

      if (
        ['image', 'font', 'media'].includes(type)
      ) {
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
          document.querySelector(
            `meta[property="${name}"]`
          ) ||
          document.querySelector(
            `meta[name="${name}"]`
          );

        return el
          ? el.getAttribute('content')
          : '';
      };

      const title =
        getMeta('og:title') ||
        document.querySelector('h1')
          ?.innerText ||
        document.title ||
        'Target Product';

      const imageUrl =
        getMeta('og:image') ||
        getMeta('twitter:image') ||
        document.querySelector('img')
          ?.src ||
        '';

      const visiblePriceCandidates =
        Array.from(
          document.querySelectorAll('body *')
        )
          .map((el) => {
            const rect =
              el.getBoundingClientRect();

            return {
              text:
                (
                  el.innerText ||
                  el.textContent ||
                  ''
                ).trim(),

              visible:
                rect.width > 0 &&
                rect.height > 0 &&
                rect.top >= 0 &&
                rect.top < 900,
            };
          })
          .filter((item) => item.visible)
          .filter((item) =>
            item.text.includes('$')
          )
          .filter(
            (item) => item.text.length <= 120
          );

      const priceCandidates =
        visiblePriceCandidates
          .map((item) => {
            const match = String(
              item.text || ''
            )
              .replace(/,/g, '')
              .match(
                /\$?\s?([0-9]+(?:\.[0-9]{1,2})?)/
              );

            return match
              ? Number(match[1])
              : null;
          })
          .filter(
            (price) =>
              price &&
              price >= 1 &&
              price <= 5000
          );

      const uniquePrices = [
        ...new Set(priceCandidates),
      ].sort((a, b) => a - b);

      const pageText = `${
        document.body.innerText || ''
      } ${
        document.documentElement.innerHTML || ''
      }`;

      const tcinMatch =
        pageText.match(
          /TCIN[^0-9]{0,20}([0-9]{6,12})/i
        ) ||
        pageText.match(
          /"tcin"\s*:\s*"?(\d{6,12})"?/i
        );

      return {
        title,
        imageUrl,

        currentPrice:
          uniquePrices[0] || 0,

        originalPrice:
          uniquePrices.length > 1
            ? uniquePrices[
                uniquePrices.length - 1
              ]
            : null,

        sku: tcinMatch
          ? tcinMatch[1]
          : null,
      };
    });

    const finalCurrentPrice =
      Math.round(
        Number(result.currentPrice || 0)
      );

    const finalOriginalPrice =
      result.originalPrice
        ? Math.round(
            Number(result.originalPrice)
          )
        : null;

    return {
      title: cleanText(result.title)
        .replace(/: Target$/, '')
        .replace('| Target', '')
        .trim(),

      sku: result.sku || null,

      retailer: 'Target',

      currentPrice:
        finalCurrentPrice || 0,

      originalPrice:
        finalOriginalPrice &&
        finalOriginalPrice >
          finalCurrentPrice
          ? finalOriginalPrice
          : null,

      originalPriceAvailable:
        Boolean(
          finalOriginalPrice &&
            finalOriginalPrice >
              finalCurrentPrice
        ),

      imageUrl:
        result.imageUrl || '',

      source:
        'target_basic_scraper_v1',
    };
  } finally {
    if (browser) {
      try {
        await browser.close();
      } catch (closeError) {
        console.error(
          'Browser close failed:',
          closeError.message
        );
      }
    }
  }
}
app.get('/debug', (req, res) => {
  res.json({
    status: 'ok',
    version: 'stable_nike_links_verification',
    nikeProductEndpoint: true,
    searchDealsEndpoint: true,
    targetEnabled: false,
  });
});

app.get('/debug-target-url', async (req, res) => {
  const url = req.query.url;

  if (!url) {
    return res.status(400).json({
      error: 'Missing Target URL',
    });
  }

  try {
    const result = await scrapeTarget(url);

    return res.json({
      status: 'ok',
      route: 'debug-target-url',
      targetEnabledInApp: false,
      result,
    });
  } catch (error) {
    console.error('DEBUG TARGET ERROR:', error.message);

    return res.status(500).json({
      status: 'error',
      route: 'debug-target-url',
      error: error.message,
    });
  }
});
app.listen(PORT, () => {
  console.log(
    `Server running on port ${PORT}`
  );
});
