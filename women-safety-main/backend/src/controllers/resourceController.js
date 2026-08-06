import Resource from '../models/Resource.js';

// @desc    Get all resources
// @route   GET /api/resources
// @access  Public
export const getResources = async (req, res) => {
  try {
    const { type, lat, lng, radius = 5000 } = req.query; // Default 5km for live search
    
    // 1. Fetch static resources (Guides & Helplines) from Database
    let dbQuery = {};
    if (type) {
      dbQuery.type = type;
    }
    
    // For 'haven', we'll search ONLY Google Places (User requested no mock data)
    const dbResources = await Resource.find(dbQuery);
    console.log(`[Resources] DB Query for "${type || 'all'}": ${dbResources.length} found`);
    let finalResources = [...dbResources];

    // 2. Fetch Live "Safe Havens" from Google Places if coordinates provided
    if ((!type || type === 'haven') && lat && lng) {
      const apiKey = process.env.GOOGLE_MAPS_API_KEY;
      if (apiKey) {
        try {
          console.log(`Searching Google Places for Safe Havens near ${lat},${lng} (radius: ${radius}m)...`);
          const typesToSearch = ['police', 'hospital', 'shopping_mall', 'transit_station', 'bus_station', 'subway_station'];
          const liveHavens = [];

          for (const placeType of typesToSearch) {
            try {
              const placesUrl = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${lat},${lng}&radius=${radius}&type=${placeType}&opennow=true&key=${apiKey}`;
              const response = await fetch(placesUrl);
              const data = await response.json();

              if (data.status === 'OK' && data.results) {
                console.log(`[GooglePlaces] Found ${data.results.length} results for: ${placeType}`);
                data.results.forEach(place => {
                  // ... mapping logic remains same ...
                  let category = 'Safe Haven';
                  let icon = 'night_shelter';
                  let color = '#F8FAFC';
                  let iconColor = '#64748B';

                  if (placeType === 'police') {
                    category = 'Police';
                    icon = 'verified_user';
                    color = '#EFF6FF';
                    iconColor = '#2563EB';
                  } else if (placeType === 'hospital') {
                    category = 'Hospital';
                    icon = 'favorite';
                    color = '#F0FDF4';
                    iconColor = '#16A34A';
                  } else if (['shopping_mall', 'transit_station', 'bus_station', 'subway_station'].includes(placeType)) {
                    category = 'Crowded Place';
                    icon = 'visibility';
                    color = '#FFF7ED';
                    iconColor = '#EA580C';
                  }

                  liveHavens.push({
                    _id: place.place_id,
                    title: place.name,
                    subtitle: place.vicinity || 'Nearby',
                    type: 'haven',
                    category,
                    icon,
                    color,
                    iconColor,
                    status: place.opening_hours?.open_now ? 'Open Now' : 'Closed/Unknown',
                    location: {
                      type: 'Point',
                      coordinates: [place.geometry.location.lng, place.geometry.location.lat],
                      address: place.vicinity
                    }
                  });
                });
              } else if (data.status !== 'ZERO_RESULTS') {
                console.warn(`[GooglePlaces] API Status for ${placeType}: ${data.status}`);
                if (data.error_message) console.warn(`[GooglePlaces] Error: ${data.error_message}`);
              }
            } catch (innerError) {
              console.error(`[GooglePlaces] Loop Error for ${placeType}:`, innerError);
              // Continue to next place type
            }
          }
          finalResources = [...liveHavens, ...finalResources];
        } catch (error) {
          console.error('[GooglePlaces] Main Fetch Error:', error);
        }
      }
    }

    res.status(200).json({
      success: true,
      count: finalResources.length,
      data: finalResources
    });
  } catch (error) {
    console.error('Get Resources Error:', error);
    res.status(500).json({ message: error.message });
  }
};

// @desc    Create a resource (Utility for seeder or admin)
// @route   POST /api/resources
// @access  Private/Admin
export const createResource = async (req, res) => {
  try {
    const resource = await Resource.create(req.body);
    res.status(201).json(resource);
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};
