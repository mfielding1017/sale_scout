const express = require('express');
const cors = require('cors');
const { chromium } = require('playwright');

const app = express();
app.use(cors());

const PORT = 3000;

app.get('/product', async (req, res) => {
  const url = req.query.url;

  if (!url) {
    return res.status(400).json({ error: 'Missing product URL' });
  }

  try {
    const product = await scrapeNike(url);

    console.log({
      title: product.title,
      currentPrice: product.currentPrice,
      originalPrice: product.originalPrice,
      source: product.source,
      debug: product.debug,
    });

    res.json(product);
  } catch (error) {
    console.error('SERVER ERROR:', error.message);

    res.status(500).json({
      error: 'Failed to fetch product',
      details: error.message,
    });
  }
});

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

async function scrapeNike(url) {
  const browser = await chromium.launch({ headless: true });

  try {
    const page = await browser.newPage({
      viewport: { width: 1400, height: 1200 },
      userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36',
    });

    await page.goto(url, {
      waitUntil: 'domcontentloaded',
      timeout: 45000,
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

      const imageUrl =
        getMeta('og:image') ||
        getMeta('twitter:image') ||
        '';

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
            tag: el.tagName,
            className: el.className ? String(el.className) : '',
            testId: el.getAttribute('data-testid') || '',
            top: rect.top,
            left: rect.left,
            width: rect.width,
            height: rect.height,
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

      return {
        title,
        imageUrl,
        currentPriceText,
        originalPriceText,
        visiblePriceCandidates,
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
      finalOriginalPrice = uniquePrices.length > 1
        ? uniquePrices[uniquePrices.length - 1]
        : null;
    }

    return {
      title: cleanNikeTitle(result.title),
      retailer: 'Nike',
      currentPrice: finalCurrentPrice || 0,
      originalPrice:
        finalOriginalPrice && finalOriginalPrice > finalCurrentPrice
          ? finalOriginalPrice
          : null,
      originalPriceAvailable:
        Boolean(finalOriginalPrice && finalOriginalPrice > finalCurrentPrice),
      imageUrl: result.imageUrl || '',
      source: 'nike_data_testid_price_parser_v3',
      betterDeal: {
        store: 'Scanning...',
        price: finalCurrentPrice || 0,
        confidence: 0,
      },
      debug: {
        currentPriceText: result.currentPriceText,
        originalPriceText: result.originalPriceText,
        visiblePriceCandidates: result.visiblePriceCandidates.slice(0, 10),
      },
    };
  } finally {
    await browser.close();
  }
}

function cleanNikeTitle(title) {
  return cleanText(title)
    .replace('| Nike', '')
    .replace('| Nike.com', '')
    .replace('. Nike.com', '')
    .trim();
}

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});