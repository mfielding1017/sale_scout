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
      viewport: { width: 1200, height: 900 },
      userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36',
    });

    await page.goto(url, {
      waitUntil: 'domcontentloaded',
      timeout: 90000,
    });

    await page.waitForTimeout(7000);

    const result = await page.evaluate(() => {
      const cleanText = (value) =>
        String(value || '').replace(/\s+/g, ' ').trim();

      const cleanPrice = (value) => {
        const match = String(value || '')
          .replace(/,/g, '')
          .match(/\$?\s*([0-9]+(?:\.[0-9]{1,2})?)/);

        return match ? Number(match[1]) : null;
      };

      const getMeta = (name) => {
        const el =
          document.querySelector(`meta[property="${name}"]`) ||
          document.querySelector(`meta[name="${name}"]`) ||
          document.querySelector(`meta[itemprop="${name}"]`);

        return el ? el.getAttribute('content') : '';
      };

      const title =
        getMeta('og:title') ||
        document.querySelector('h1')?.innerText ||
        document.title ||
        'Target Product';

      const imageUrl =
        getMeta('og:image') ||
        getMeta('twitter:image') ||
        document.querySelector('img')?.src ||
        '';

      let currentPrice = null;
      let originalPrice = null;
      let priceSource = 'none';

      const metaPrice =
        getMeta('price') ||
        getMeta('product:price:amount') ||
        getMeta('og:price:amount');

      if (metaPrice) {
        currentPrice = cleanPrice(metaPrice);
        if (currentPrice) priceSource = 'meta_price';
      }

      if (!currentPrice) {
        const jsonLdScripts = Array.from(
          document.querySelectorAll('script[type="application/ld+json"]')
        );

        for (const script of jsonLdScripts) {
          try {
            const parsed = JSON.parse(script.textContent || '{}');
            const items = Array.isArray(parsed) ? parsed : [parsed];

            for (const item of items) {
              const offers = item.offers || item.offers?.[0];

              if (offers) {
                const offer = Array.isArray(offers) ? offers[0] : offers;
                const possiblePrice = offer.price || offer.lowPrice;

                if (possiblePrice) {
                  currentPrice = cleanPrice(possiblePrice);
                  if (currentPrice) {
                    priceSource = 'json_ld_offer';
                    break;
                  }
                }
              }
            }

            if (currentPrice) break;
          } catch (_) {}
        }
      }

      const fullHtml = document.documentElement.innerHTML || '';
      const fullText = document.body.innerText || '';

      if (!currentPrice) {
        const regexCandidates = [
          /"current_retail"\s*:\s*([0-9]+(?:\.[0-9]{1,2})?)/i,
          /"formatted_current_price"\s*:\s*"\$?([0-9]+(?:\.[0-9]{1,2})?)"/i,
          /"price"\s*:\s*"\$?([0-9]+(?:\.[0-9]{1,2})?)"/i,
          /"currentPrice"\s*:\s*"\$?([0-9]+(?:\.[0-9]{1,2})?)"/i,
        ];

        for (const regex of regexCandidates) {
          const match = fullHtml.match(regex);
          if (match && match[1]) {
            currentPrice = Number(match[1]);
            priceSource = 'embedded_json_regex';
            break;
          }
        }
      }

      if (!currentPrice) {
        const visiblePriceCandidates = Array.from(
          document.querySelectorAll('body *')
        )
          .map((el) => {
            const rect = el.getBoundingClientRect();

            return {
              text: cleanText(el.innerText || el.textContent || ''),
              visible:
                rect.width > 0 &&
                rect.height > 0 &&
                rect.top >= 0 &&
                rect.top < 1000,
            };
          })
          .filter((item) => item.visible)
          .filter((item) => item.text.includes('$'))
          .filter((item) => item.text.length <= 80)
          .map((item) => cleanPrice(item.text))
          .filter((price) => price && price >= 1 && price <= 5000);

        const uniquePrices = [...new Set(visiblePriceCandidates)].sort(
          (a, b) => a - b
        );

        if (uniquePrices.length > 0) {
          currentPrice = uniquePrices[0];
          originalPrice =
            uniquePrices.length > 1 ? uniquePrices[uniquePrices.length - 1] : null;
          priceSource = 'visible_price_candidates';
        }
      }

      const pageText = `${fullText} ${fullHtml}`;

      const tcinMatch =
        pageText.match(/TCIN[^0-9]{0,20}([0-9]{6,12})/i) ||
        pageText.match(/"tcin"\s*:\s*"?(\d{6,12})"?/i);

      return {
        title: cleanText(title),
        imageUrl,
        currentPrice: currentPrice || 0,
        originalPrice: originalPrice || null,
        sku: tcinMatch ? tcinMatch[1] : null,
        priceSource,
      };
    });

    const finalCurrentPrice = Math.round(Number(result.currentPrice || 0));
    const finalOriginalPrice = result.originalPrice
      ? Math.round(Number(result.originalPrice))
      : null;

    return {
      title: cleanText(result.title)
        .replace(/: Target$/, '')
        .replace('| Target', '')
        .trim(),
      sku: result.sku || null,
      retailer: 'Target',
      currentPrice: finalCurrentPrice || 0,
      originalPrice:
        finalOriginalPrice && finalOriginalPrice > finalCurrentPrice
          ? finalOriginalPrice
          : null,
      originalPriceAvailable: Boolean(
        finalOriginalPrice && finalOriginalPrice > finalCurrentPrice
      ),
      imageUrl: result.imageUrl || '',
      source: 'target_price_extraction_v2',
      debugPriceSource: result.priceSource,
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
app.get('/debug-target-html', async (req, res) => {
  const url = req.query.url;

  if (!url) {
    return res.status(400).json({
      error: 'Missing Target URL',
    });
  }

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

    await page.goto(url, {
      waitUntil: 'domcontentloaded',
      timeout: 90000,
    });

    await page.waitForTimeout(7000);

    const result = await page.evaluate(() => {
      const html = document.documentElement.innerHTML || '';
      const text = document.body.innerText || '';

      return {
        title: document.title,
        textIncludesDollar: text.includes('$'),
        htmlIncludesCurrentRetail: html.includes('current_retail'),
        htmlIncludesFormattedCurrentPrice: html.includes('formatted_current_price'),
        htmlIncludesPrice: html.includes('price'),
        htmlIncludesTCIN: html.includes('TCIN') || html.includes('tcin'),
        textSample: text.slice(0, 3000),
        htmlSample: html.slice(0, 5000),
      };
    });

    return res.json({
      status: 'ok',
      route: 'debug-target-html',
      result,
    });
  } catch (error) {
    return res.status(500).json({
      status: 'error',
      route: 'debug-target-html',
      error: error.message,
    });
  } finally {
    if (browser) {
      try {
        await browser.close();
      } catch (_) {}
    }
  }
});
app.get('/debug-target-scripts', async (req, res) => {
  const url = req.query.url;

  if (!url) {
    return res.status(400).json({
      error: 'Missing Target URL',
    });
  }

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

    await page.goto(url, {
      waitUntil: 'domcontentloaded',
      timeout: 90000,
    });

    await page.waitForTimeout(7000);

    const result = await page.evaluate(() => {
      const scripts = Array.from(document.querySelectorAll('script'))
        .map((script, index) => {
          const text = script.textContent || '';

          return {
            index,
            length: text.length,
            includesPrice: text.toLowerCase().includes('price'),
            includesTCIN:
              text.toLowerCase().includes('tcin') ||
              text.includes('94784166'),
            includesCurrentRetail: text.includes('current_retail'),
            includesFormattedPrice: text.includes('formatted_current_price'),
            sample: text.slice(0, 1000),
          };
        })
        .filter(
          (script) =>
            script.includesPrice ||
            script.includesTCIN ||
            script.includesCurrentRetail ||
            script.includesFormattedPrice
        );

      return {
        scriptCount: document.querySelectorAll('script').length,
        matchingScripts: scripts.slice(0, 10),
      };
    });

    return res.json({
      status: 'ok',
      route: 'debug-target-scripts',
      result,
    });
  } catch (error) {
    return res.status(500).json({
      status: 'error',
      route: 'debug-target-scripts',
      error: error.message,
    });
  } finally {
    if (browser) {
      try {
        await browser.close();
      } catch (_) {}
    }
  }
});
app.get('/debug-target-network', async (req, res) => {
  const url = req.query.url;

  if (!url) {
    return res.status(400).json({
      error: 'Missing Target URL',
    });
  }

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

    const interestingRequests = [];

    page.on('request', (request) => {
      const requestUrl = request.url();
      const lower = requestUrl.toLowerCase();

      if (
        lower.includes('redsky') ||
        lower.includes('price') ||
        lower.includes('tcin') ||
        lower.includes('product')
      ) {
        interestingRequests.push({
          method: request.method(),
          url: requestUrl,
        });
      }
    });

    await page.goto(url, {
      waitUntil: 'domcontentloaded',
      timeout: 90000,
    });

    await page.waitForTimeout(7000);

    return res.json({
      status: 'ok',
      route: 'debug-target-network',
      requestCount: interestingRequests.length,
      requests: interestingRequests.slice(0, 30),
    });
  } catch (error) {
    return res.status(500).json({
      status: 'error',
      route: 'debug-target-network',
      error: error.message,
    });
  } finally {
    if (browser) {
      try {
        await browser.close();
      } catch (_) {}
    }
  }
});
app.get('/debug-target-responses', async (req, res) => {
  const url = req.query.url;

  if (!url) {
    return res.status(400).json({
      error: 'Missing Target URL',
    });
  }

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

    const interestingResponses = [];

    page.on('response', async (response) => {
      try {
        const responseUrl = response.url();
        const lower = responseUrl.toLowerCase();
        const contentType = response.headers()['content-type'] || '';

        if (
          lower.includes('redsky') ||
          lower.includes('price') ||
          lower.includes('tcin') ||
          lower.includes('product') ||
          contentType.includes('application/json')
        ) {
          const text = await response.text();

          if (
            text.toLowerCase().includes('price') ||
            text.toLowerCase().includes('tcin') ||
            text.includes('94784166')
          ) {
            interestingResponses.push({
              url: responseUrl,
              status: response.status(),
              contentType,
              includesPrice: text.toLowerCase().includes('price'),
              includesTCIN:
                text.toLowerCase().includes('tcin') ||
                text.includes('94784166'),
              sample: text.slice(0, 1500),
            });
          }
        }
      } catch (_) {}
    });

    await page.goto(url, {
      waitUntil: 'domcontentloaded',
      timeout: 90000,
    });

    await page.waitForTimeout(10000);

    return res.json({
      status: 'ok',
      route: 'debug-target-responses',
      responseCount: interestingResponses.length,
      responses: interestingResponses.slice(0, 10),
    });
  } catch (error) {
    return res.status(500).json({
      status: 'error',
      route: 'debug-target-responses',
      error: error.message,
    });
  } finally {
    if (browser) {
      try {
        await browser.close();
      } catch (_) {}
    }
  }
});
app.get('/debug-target-price-responses', async (req, res) => {
  const url = req.query.url;

  if (!url) {
    return res.status(400).json({
      error: 'Missing Target URL',
    });
  }

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

    const matches = [];

    page.on('response', async (response) => {
      try {
        const responseUrl = response.url();
        const contentType = response.headers()['content-type'] || '';

        if (!contentType.includes('application/json')) return;

        const text = await response.text();
        const lower = text.toLowerCase();

        if (
          lower.includes('current_retail') ||
          lower.includes('formatted_current_price') ||
          lower.includes('"price"') ||
          lower.includes('94784166') ||
          lower.includes('sunscreen spray')
        ) {
          matches.push({
            url: responseUrl,
            status: response.status(),
            contentType,
            includesCurrentRetail: lower.includes('current_retail'),
            includesFormattedCurrentPrice: lower.includes(
              'formatted_current_price'
            ),
            includesPrice: lower.includes('"price"'),
            includesTCIN: text.includes('94784166'),
            includesTitle: lower.includes('sunscreen spray'),
            sample: text.slice(0, 3000),
          });
        }
      } catch (_) {}
    });

    await page.goto(url, {
      waitUntil: 'domcontentloaded',
      timeout: 90000,
    });

    await page.waitForTimeout(12000);

    return res.json({
      status: 'ok',
      route: 'debug-target-price-responses',
      matchCount: matches.length,
      matches: matches.slice(0, 8),
    });
  } catch (error) {
    return res.status(500).json({
      status: 'error',
      route: 'debug-target-price-responses',
      error: error.message,
    });
  } finally {
    if (browser) {
      try {
        await browser.close();
      } catch (_) {}
    }
  }
});
app.listen(PORT, () => {
  console.log(
    `Server running on port ${PORT}`
  );
});
